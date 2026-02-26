"use client";

import { createClient } from "@supabase/supabase-js";
import Link from "next/link";
import { FormEvent, useEffect, useMemo, useState } from "react";

type ViewState =
  | "checking"
  | "ready"
  | "missing_link"
  | "config_missing"
  | "success"
  | "error";

function parseHashParams(hash: string): URLSearchParams {
  const trimmed = hash.startsWith("#") ? hash.slice(1) : hash;
  return new URLSearchParams(trimmed);
}

function parseQueryParams(search: string): URLSearchParams {
  const trimmed = search.startsWith("?") ? search.slice(1) : search;
  return new URLSearchParams(trimmed);
}

export default function ResetPasswordPage() {
  const [password, setPassword] = useState("");
  const [confirmPassword, setConfirmPassword] = useState("");
  const [message, setMessage] = useState<string>("");
  const [isWorking, setIsWorking] = useState(false);
  const [viewState, setViewState] = useState<ViewState>("checking");

  const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const supabaseAnonKey = process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;

  const supabase = useMemo(() => {
    if (!supabaseUrl || !supabaseAnonKey) return null;
    return createClient(supabaseUrl, supabaseAnonKey);
  }, [supabaseAnonKey, supabaseUrl]);

  useEffect(() => {
    let cancelled = false;

    async function bootstrap() {
      if (!supabase) {
        if (!cancelled) {
          setViewState("config_missing");
          setMessage("Web reset is not configured yet. Missing Supabase public environment variables.");
        }
        return;
      }

      const searchParams = parseQueryParams(window.location.search);
      const hashParams = parseHashParams(window.location.hash);
      const type = hashParams.get("type") ?? searchParams.get("type");

      if (type !== "recovery") {
        if (!cancelled) {
          setViewState("missing_link");
          setMessage("Open this page from the password reset email link to set a new password.");
        }
        return;
      }

      const code = searchParams.get("code");
      let error: Error | null = null;

      if (code) {
        const result = await supabase.auth.exchangeCodeForSession(code);
        error = result.error;
      } else {
        const accessToken = hashParams.get("access_token");
        const refreshToken = hashParams.get("refresh_token");

        if (!accessToken || !refreshToken) {
          if (!cancelled) {
            setViewState("missing_link");
            setMessage("Open this page from the password reset email link to set a new password.");
          }
          return;
        }

        const result = await supabase.auth.setSession({
          access_token: accessToken,
          refresh_token: refreshToken
        });
        error = result.error;
      }

      if (cancelled) return;

      if (error) {
        setViewState("error");
        setMessage(error.message);
        return;
      }

      setViewState("ready");
      setMessage("Enter your new password below.");
      window.history.replaceState(null, "", window.location.pathname);
    }

    void bootstrap();
    return () => {
      cancelled = true;
    };
  }, [supabase]);

  async function onSubmit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!supabase) return;

    if (password.trim().length < 6) {
      setViewState("error");
      setMessage("Password must be at least 6 characters.");
      return;
    }
    if (password !== confirmPassword) {
      setViewState("error");
      setMessage("Passwords do not match.");
      return;
    }

    setIsWorking(true);
    setMessage("");
    const { error } = await supabase.auth.updateUser({ password });
    setIsWorking(false);

    if (error) {
      setViewState("error");
      setMessage(error.message);
      return;
    }

    setViewState("success");
    setMessage("Your password has been updated. Return to the Speakance app and sign in.");
    setPassword("");
    setConfirmPassword("");
  }

  const showForm = viewState === "ready" || viewState === "error";

  return (
    <main className="docShell">
      <section className="panel docCard" style={{ maxWidth: 640, margin: "0 auto" }}>
        <div className="eyebrow">Password Reset</div>
        <h1>Reset your password</h1>
        <p>Use this page after tapping the password reset email link from Speakance.</p>

        <div className={`statusBox ${viewState}`}>
          {message || (viewState === "checking" ? "Checking reset link..." : "")}
        </div>

        {showForm && (
          <form onSubmit={onSubmit} className="authFormWeb">
            <label className="fieldLabel" htmlFor="new-password">
              New password
            </label>
            <input
              id="new-password"
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              className="fieldInput"
              minLength={6}
              autoComplete="new-password"
              required
            />

            <label className="fieldLabel" htmlFor="confirm-password">
              Confirm password
            </label>
            <input
              id="confirm-password"
              type="password"
              value={confirmPassword}
              onChange={(e) => setConfirmPassword(e.target.value)}
              className="fieldInput"
              minLength={6}
              autoComplete="new-password"
              required
            />

            <button className="btn btnPrimary submitBtn" type="submit" disabled={isWorking}>
              {isWorking ? "Updating..." : "Update Password"}
            </button>
          </form>
        )}

        <div className="ctaRow">
          <Link className="btn btnGhost" href="/">
            Home
          </Link>
          <Link className="btn btnGhost" href="/support">
            Support
          </Link>
        </div>
      </section>
    </main>
  );
}
