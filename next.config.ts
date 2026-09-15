import type { NextConfig } from "next";

const nextConfig: NextConfig = {
  reactCompiler: true,
  serverExternalPackages: ["pdfkit"],
  experimental: { serverActions: { bodySizeLimit: "11mb" } },
  outputFileTracingIncludes: {
    "/api/dossiers/*/comptes-de-gestion/*/document": [
      "./node_modules/@expo-google-fonts/noto-sans/400Regular/NotoSans_400Regular.ttf",
      "./node_modules/@expo-google-fonts/noto-sans/700Bold/NotoSans_700Bold.ttf",
      "./node_modules/@expo-google-fonts/noto-sans/package.json",
    ],
  },
};

export default nextConfig;
