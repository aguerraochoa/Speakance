"use client";

import { useEffect } from "react";

function hasAuthReturnParams(searchParams: URLSearchParams, hashParams: URLSearchParams): boolean {
  const keys = ["access_token", "refresh_token", "type", "code", "token_hash"];
  return keys.some((key) => searchParams.has(key) || hashParams.has(key));
}

function parseHashParams(hash: string): URLSearchParams {
  const trimmed = hash.startsWith("#") ? hash.slice(1) : hash;
  return new URLSearchParams(trimmed);
}

export default function AuthRedirectBridge() {
  useEffect(() => {
    const searchParams = new URLSearchParams(window.location.search);
    const hashParams = parseHashParams(window.location.hash);

    if (!hasAuthReturnParams(searchParams, hashParams)) return;

    const type = hashParams.get("type") ?? searchParams.get("type");
    const search = window.location.search;
    const hash = window.location.hash;

    if (type === "recovery") {
      window.location.replace(`/auth/reset${search}${hash}`);
      return;
    }

    if (type === "signup") {
      window.location.replace("/auth/confirmed");
    }
  }, []);

  return null;
}
