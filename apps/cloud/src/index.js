// Cloudflare needs an ES module with a default export; all logic is Jac,
// compiled to build/js by `jac run build.jac` (see worker.cl.jac).
import { handle } from "../build/js/worker.js";

export default {
  fetch: (request, env, ctx) => handle(request, env, ctx),
};
