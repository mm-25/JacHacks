"""OAuth 2.1 authorization server for the Sherry MCP connector.

claude.ai and ChatGPT register themselves (Dynamic Client Registration), send
the user to the Sherry sign-in page (`/sherry/login`), and exchange the
resulting code (PKCE S256, verified by the MCP SDK) for tokens. Each token is
linked to the user's Sherry account token, which is what the tools use to
call the Sherry API as that user.

Implements the MCP SDK's `OAuthAuthorizationServerProvider` protocol (duck
typed). State is kept in a JSON file (hashed tokens, mode 600) so a restart
doesn't disconnect everyone; authorization codes and pending sign-ins live
in memory for a few minutes only.
"""

import os;
import json;
import time;
import hashlib;
import secrets;
import from pathlib { Path }
import from mcp.shared.auth { OAuthClientInformationFull, OAuthToken }
import from mcp.server.auth.provider {
    AuthorizationParams,
    AuthorizationCode,
    RefreshToken,
    AccessToken,
    TokenError,
    construct_redirect_uri
}

glob:pub SCOPE: str = "sherry.memories";
glob ACCESS_TTL_SECONDS: int = 8 * 3600;
glob REFRESH_TTL_SECONDS: int = 30 * 24 * 3600;
glob CODE_TTL_SECONDS: int = 300;
glob PENDING_TTL_SECONDS: int = 900;


def _hash(token: str) -> str {
    return hashlib.sha256(token.encode("utf-8")).hexdigest();
}


def _now -> int {
    return int(time.time());
}


obj SherryOAuthProvider {
    has public_url: str,
        resource_url: str,
        data_file: str,
        clients: dict = {},
        access_tokens: dict = {},
        refresh_tokens: dict = {},
        pending: dict = {},
        codes: dict = {};

    def postinit {
        self.clients = {};
        self.access_tokens = {};
        self.refresh_tokens = {};
        self.pending = {};
        self.codes = {};
        self._load();
    }

    # ---------- persistence ----------

    def _load {
        path = Path(self.data_file);
        if not path.exists() {
            return;
        }
        try {
            data: dict = json.loads(path.read_text()) as dict;
            self.clients = (data.get("clients") or {}) as dict;
            self.access_tokens = (data.get("access_tokens") or {}) as dict;
            self.refresh_tokens = (data.get("refresh_tokens") or {}) as dict;
        } except Exception {
            print(f"[sherry-mcp] could not read {self.data_file}; starting with no connections");
        }
    }

    def _save {
        path = Path(self.data_file);
        path.parent.mkdir(parents=True, exist_ok=True);
        now = _now();
        self.access_tokens = {
            k: v
            for (k, v) in self.access_tokens.items()
            if int(v["expires_at"]) > now
        };
        self.refresh_tokens = {
            k: v
            for (k, v) in self.refresh_tokens.items()
            if int(v["expires_at"]) > now
        };
        tmp = path.with_suffix(".tmp");
        tmp.write_text(
            json.dumps(
                {
                    "clients": self.clients,
                    "access_tokens": self.access_tokens,
                    "refresh_tokens": self.refresh_tokens
                }
            )
        );
        os.chmod(tmp, 0o600);
        tmp.replace(path);
    }

    # ---------- client registration ----------

    async def get_client(client_id: str) -> OAuthClientInformationFull | None {
        stored = self.clients.get(client_id);
        return OAuthClientInformationFull.model_validate(stored) if stored else None;
    }

    async def register_client(client_info: OAuthClientInformationFull) {
        self.clients[str(client_info.client_id)] = client_info.model_dump(mode="json");
        self._save();
    }

    # ---------- authorization (sign-in page) ----------

    async def authorize(client: OAuthClientInformationFull, params: AuthorizationParams) -> str {
        request_id = secrets.token_urlsafe(24);
        self.pending[request_id] = {
            "client_id": str(client.client_id),
            "params": params.model_dump(mode="json"),
            "created": _now()
        };
        return f"{self.public_url}/sherry/login?request={request_id}";
    }

    """The pending sign-in behind a login page, or None if unknown/expired."""
    def pending_request(request_id: str) -> dict | None {
        entry = self.pending.get(request_id);
        if not entry or _now() - int(entry["created"]) > PENDING_TTL_SECONDS {
            return None;
        }
        return entry as dict;
    }

    def client_label(client_id: str) -> str {
        stored: dict = (self.clients.get(client_id) or {}) as dict;
        return str(stored.get("client_name") or "An AI assistant");
    }

    """User approved on the sign-in page: mint a code, return the redirect URL."""
    def complete_sign_in(request_id: str, email: str, sherry_token: str) -> str {
        entry: dict = self.pending.pop(request_id) as dict;
        params: dict = entry["params"] as dict;
        code = secrets.token_urlsafe(32);
        self.codes[code] = {
            "code": AuthorizationCode(
                code=code,
                scopes=params.get("scopes") or [SCOPE],
                expires_at=float(_now() + CODE_TTL_SECONDS),
                client_id=str(entry["client_id"]),
                code_challenge=str(params["code_challenge"]),
                redirect_uri=params["redirect_uri"],
                redirect_uri_provided_explicitly=bool(params["redirect_uri_provided_explicitly"]),
                resource=params.get("resource") or self.resource_url,
                subject=email
            ),
            "sherry_token": sherry_token
        };
        return construct_redirect_uri(
            str(params["redirect_uri"]), code=code, state=params.get("state") as str | None
        );
    }

    """User cancelled on the sign-in page: tell the client, per RFC 6749."""
    def deny_sign_in(request_id: str) -> str {
        entry: dict = self.pending.pop(request_id) as dict;
        params: dict = entry["params"] as dict;
        return construct_redirect_uri(
            str(params["redirect_uri"]),
            error="access_denied",
            error_description="The user declined to connect Sherry.",
            state=params.get("state") as str | None
        );
    }

    # ---------- codes and tokens ----------

    async def load_authorization_code(
        client: OAuthClientInformationFull, authorization_code: str
    ) -> AuthorizationCode | None {
        entry = self.codes.get(authorization_code);
        if not entry {
            return None;
        }
        code: AuthorizationCode = entry["code"] as AuthorizationCode;
        if code.client_id != str(client.client_id) or code.expires_at < time.time() {
            return None;
        }
        return code;
    }

    def _issue(
        client_id: str,
        scopes: list[str],
        resource: str | None,
        subject: str | None,
        sherry_token: str
    ) -> OAuthToken {
        access = secrets.token_urlsafe(32);
        refresh = secrets.token_urlsafe(32);
        family = secrets.token_hex(8);
        now = _now();
        record = {
            "client_id": client_id,
            "scopes": scopes,
            "resource": resource or self.resource_url,
            "subject": subject,
            "sherry_token": sherry_token,
            "family": family
        };
        self.access_tokens[_hash(access)] = {**record, "expires_at": now + ACCESS_TTL_SECONDS};
        self.refresh_tokens[_hash(refresh)] = {**record, "expires_at": now + REFRESH_TTL_SECONDS};
        self._save();
        return OAuthToken(
            access_token=access,
            token_type="Bearer",
            expires_in=ACCESS_TTL_SECONDS,
            refresh_token=refresh,
            scope=" ".join(scopes)
        );
    }

    async def exchange_authorization_code(
        client: OAuthClientInformationFull, authorization_code: AuthorizationCode
    ) -> OAuthToken {
        entry = self.codes.pop(authorization_code.code, None);
        if not entry {
            raise TokenError(error="invalid_grant", error_description="Code already used.");
        }
        return self._issue(
            str(client.client_id),
            authorization_code.scopes,
            authorization_code.resource,
            authorization_code.subject,
            str(entry["sherry_token"])
        );
    }

    async def load_refresh_token(
        client: OAuthClientInformationFull, refresh_token: str
    ) -> RefreshToken | None {
        rec = self.refresh_tokens.get(_hash(refresh_token));
        if not rec or rec["client_id"] != str(client.client_id) or int(rec["expires_at"]) < _now() {
            return None;
        }
        return RefreshToken(
            token=refresh_token,
            client_id=str(rec["client_id"]),
            scopes=list(rec["scopes"]),
            expires_at=int(rec["expires_at"]),
            resource=rec.get("resource"),
            subject=rec.get("subject")
        );
    }

    def _revoke_family(family: str) {
        self.access_tokens = {
            k: v
            for (k, v) in self.access_tokens.items()
            if v.get("family") != family
        };
        self.refresh_tokens = {
            k: v
            for (k, v) in self.refresh_tokens.items()
            if v.get("family") != family
        };
    }

    async def exchange_refresh_token(
        client: OAuthClientInformationFull, refresh_token: RefreshToken, scopes: list[str]
    ) -> OAuthToken {
        rec = self.refresh_tokens.get(_hash(refresh_token.token));
        if not rec {
            raise TokenError(error="invalid_grant", error_description="Refresh token is no longer valid.");
        }
        # Rotate: the old access + refresh tokens stop working.
        self._revoke_family(str(rec["family"]));
        return self._issue(
            str(client.client_id),
            scopes or list(rec["scopes"]),
            rec.get("resource") as str | None,
            rec.get("subject") as str | None,
            str(rec["sherry_token"])
        );
    }

    async def load_access_token(token: str) -> AccessToken | None {
        rec = self.access_tokens.get(_hash(token));
        if not rec or int(rec["expires_at"]) < _now() {
            return None;
        }
        return AccessToken(
            token=token,
            client_id=str(rec["client_id"]),
            scopes=list(rec["scopes"]),
            expires_at=int(rec["expires_at"]),
            resource=rec.get("resource"),
            subject=rec.get("subject")
        );
    }

    async def revoke_token(token: any) {
        digest = _hash(str(token.token));
        rec = self.access_tokens.get(digest) or self.refresh_tokens.get(digest);
        if rec {
            self._revoke_family(str(rec["family"]));
            self._save();
        }
    }

    """The Sherry account token behind an MCP access token."""
    def sherry_token_for(access_token: str) -> str | None {
        rec = self.access_tokens.get(_hash(access_token));
        return str(rec["sherry_token"]) if rec else None;
    }
}
