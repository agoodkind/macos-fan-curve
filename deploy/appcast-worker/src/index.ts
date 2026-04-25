export default {
  async fetch(request: Request, env: { ASSETS: Fetcher }): Promise<Response> {
    const url = new URL(request.url)

    if (!url.pathname.startsWith("/fancurve")) {
      return new Response("Not found", { status: 404 })
    }

    const assetPath =
      url.pathname === "/fancurve" || url.pathname === "/fancurve/"
      ? "/appcast.xml"
      : url.pathname.slice("/fancurve".length)

    const assetURL = new URL(assetPath, "https://assets.local")
    return env.ASSETS.fetch(assetURL)
  },
}
