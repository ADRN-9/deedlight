import type { MetadataRoute } from "next";

export default function manifest(): MetadataRoute.Manifest {
  return {
    name: "Deedlight",
    short_name: "Deedlight",
    description: "A daily space for goodness, beauty, and better deeds.",
    start_url: "/today",
    scope: "/",
    display: "standalone",
    background_color: "#FFF8EA",
    theme_color: "#D9A441",
    orientation: "portrait",
    categories: ["lifestyle", "social", "productivity"],
    icons: [
      {
        src: "/icons/deedlight-192.png",
        sizes: "192x192",
        type: "image/png",
        purpose: "any"
      },
      {
        src: "/icons/deedlight-512.png",
        sizes: "512x512",
        type: "image/png",
        purpose: "any"
      },
      {
        src: "/icons/deedlight-maskable-512.png",
        sizes: "512x512",
        type: "image/png",
        purpose: "maskable"
      }
    ]
  };
}
