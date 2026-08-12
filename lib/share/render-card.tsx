import { ImageResponse } from "next/og";
import {
  DEEDLIGHT_SITE_NAME,
  DEEDLIGHT_TAGLINE,
} from "@/lib/share/site";

type ShareCardInput = {
  eyebrow?: string;
  title: string;
  description?: string | null;
  meta?: string | null;
};

export function renderShareCard({
  eyebrow = "DEEDLIGHT",
  title,
  description,
  meta,
}: ShareCardInput) {
  return new ImageResponse(
    (
      <div
        style={{
          width: "100%",
          height: "100%",
          display: "flex",
          flexDirection: "column",
          justifyContent: "space-between",
          background:
            "radial-gradient(circle at 78% 16%, rgba(244,199,107,0.50), transparent 27%), linear-gradient(135deg, #FFF9EE 0%, #F7EBD3 100%)",
          color: "#26231F",
          padding: "64px 72px",
          fontFamily: "Arial, Helvetica, sans-serif",
        }}
      >
        <div
          style={{
            display: "flex",
            flexDirection: "column",
            maxWidth: "980px",
          }}
        >
          <div
            style={{
              display: "flex",
              alignSelf: "flex-start",
              border: "2px solid rgba(217,164,65,0.48)",
              borderRadius: "999px",
              padding: "10px 18px",
              fontSize: "18px",
              fontWeight: 800,
              letterSpacing: "0.16em",
              color: "#7A5816",
              background: "rgba(255,255,255,0.78)",
            }}
          >
            {eyebrow}
          </div>

          <div
            style={{
              display: "flex",
              marginTop: "30px",
              fontSize: title.length > 72 ? "56px" : "68px",
              lineHeight: 1.04,
              fontWeight: 800,
              letterSpacing: "-0.035em",
            }}
          >
            {title}
          </div>

          {description ? (
            <div
              style={{
                display: "flex",
                marginTop: "26px",
                maxWidth: "920px",
                fontSize: "28px",
                lineHeight: 1.38,
                color: "#5F5548",
              }}
            >
              {description}
            </div>
          ) : null}

          {meta ? (
            <div
              style={{
                display: "flex",
                alignSelf: "flex-start",
                marginTop: "28px",
                borderRadius: "999px",
                padding: "10px 18px",
                fontSize: "19px",
                fontWeight: 700,
                color: "#6A5225",
                background: "rgba(255,255,255,0.72)",
              }}
            >
              {meta}
            </div>
          ) : null}
        </div>

        <div
          style={{
            display: "flex",
            alignItems: "center",
            justifyContent: "space-between",
            borderTop: "2px solid rgba(217,164,65,0.28)",
            paddingTop: "24px",
          }}
        >
          <div
            style={{
              display: "flex",
              alignItems: "center",
              fontSize: "27px",
              fontWeight: 800,
            }}
          >
            <div
              style={{
                display: "flex",
                width: "42px",
                height: "42px",
                alignItems: "center",
                justifyContent: "center",
                marginRight: "14px",
                borderRadius: "999px",
                background: "#D9A441",
                fontSize: "23px",
              }}
            >
              ✦
            </div>
            {DEEDLIGHT_SITE_NAME}
          </div>

          <div
            style={{
              display: "flex",
              fontSize: "21px",
              fontWeight: 700,
              color: "#7A6C58",
            }}
          >
            {DEEDLIGHT_TAGLINE}
          </div>
        </div>
      </div>
    ),
    {
      width: 1200,
      height: 630,
    },
  );
}

export function withShareCache(response: ImageResponse) {
  response.headers.set(
    "Cache-Control",
    "public, max-age=300, s-maxage=3600, stale-while-revalidate=86400",
  );
  return response;
}
