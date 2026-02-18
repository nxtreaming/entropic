import { Billing } from "../components/Billing";
import { useEffect, useState } from "react";
import { Mail } from "lucide-react";
import { useAuth } from "../contexts/AuthContext";
import {
  signInWithGoogle,
  signInWithDiscord,
  signInWithEmail,
  signUpWithEmail,
} from "../lib/auth";
import {
  getLocalCreditBalance,
  getLocalUsageSummary,
  LocalBalanceResponse,
  LocalUsageResponse,
} from "../lib/localCredits";

function GoogleIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24">
      <path
        fill="#4285F4"
        d="M22.56 12.25c0-.78-.07-1.53-.2-2.25H12v4.26h5.92c-.26 1.37-1.04 2.53-2.21 3.31v2.77h3.57c2.08-1.92 3.28-4.74 3.28-8.09z"
      />
      <path
        fill="#34A853"
        d="M12 23c2.97 0 5.46-.98 7.28-2.66l-3.57-2.77c-.98.66-2.23 1.06-3.71 1.06-2.86 0-5.29-1.93-6.16-4.53H2.18v2.84C3.99 20.53 7.7 23 12 23z"
      />
      <path
        fill="#FBBC05"
        d="M5.84 14.09c-.22-.66-.35-1.36-.35-2.09s.13-1.43.35-2.09V7.07H2.18C1.43 8.55 1 10.22 1 12s.43 3.45 1.18 4.93l2.85-2.22.81-.62z"
      />
      <path
        fill="#EA4335"
        d="M12 5.38c1.62 0 3.06.56 4.21 1.64l3.15-3.15C17.45 2.09 14.97 1 12 1 7.7 1 3.99 3.47 2.18 7.07l3.66 2.84c.87-2.6 3.3-4.53 6.16-4.53z"
      />
    </svg>
  );
}

function DiscordIcon({ className }: { className?: string }) {
  return (
    <svg className={className} viewBox="0 0 24 24" fill="currentColor">
      <path d="M20.317 4.37a19.791 19.791 0 0 0-4.885-1.515.074.074 0 0 0-.079.037c-.21.375-.444.864-.608 1.25a18.27 18.27 0 0 0-5.487 0 12.64 12.64 0 0 0-.617-1.25.077.077 0 0 0-.079-.037A19.736 19.736 0 0 0 3.677 4.37a.07.07 0 0 0-.032.027C.533 9.046-.32 13.58.099 18.057a.082.082 0 0 0 .031.057 19.9 19.9 0 0 0 5.993 3.03.078.078 0 0 0 .084-.028 14.09 14.09 0 0 0 1.226-1.994.076.076 0 0 0-.041-.106 13.107 13.107 0 0 1-1.872-.892.077.077 0 0 1-.008-.128 10.2 10.2 0 0 0 .372-.292.074.074 0 0 1 .077-.01c3.928 1.793 8.18 1.793 12.062 0a.074.074 0 0 1 .078.01c.12.098.246.198.373.292a.077.077 0 0 1-.006.127 12.299 12.299 0 0 1-1.873.892.077.077 0 0 0-.041.107c.36.698.772 1.362 1.225 1.993a.076.076 0 0 0 .084.028 19.839 19.839 0 0 0 6.002-3.03.077.077 0 0 0 .032-.054c.5-5.177-.838-9.674-3.549-13.66a.061.061 0 0 0-.031-.03zM8.02 15.33c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.956-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.956 2.418-2.157 2.418zm7.975 0c-1.183 0-2.157-1.085-2.157-2.419 0-1.333.955-2.419 2.157-2.419 1.21 0 2.176 1.096 2.157 2.42 0 1.333-.946 2.418-2.157 2.418z" />
    </svg>
  );
}

type BillingAuthLoading =
  | null
  | "google"
  | "discord"
  | "email-signin"
  | "email-signup";

export function BillingPage() {
  const { isAuthenticated, isAuthConfigured } = useAuth();
  const [localBalance, setLocalBalance] = useState<LocalBalanceResponse | null>(null);
  const [localUsage, setLocalUsage] = useState<LocalUsageResponse | null>(null);
  const [showEmailAuth, setShowEmailAuth] = useState(false);
  const [emailAuthMode, setEmailAuthMode] = useState<"signin" | "signup">("signin");
  const [authEmail, setAuthEmail] = useState("");
  const [authPassword, setAuthPassword] = useState("");
  const [authError, setAuthError] = useState<string | null>(null);
  const [authNotice, setAuthNotice] = useState<string | null>(null);
  const [authLoading, setAuthLoading] = useState<BillingAuthLoading>(null);

  useEffect(() => {
    if (isAuthenticated || !isAuthConfigured) {
      return;
    }
    let cancelled = false;
    const load = async () => {
      const [balanceResult, usageResult] = await Promise.allSettled([
        getLocalCreditBalance(),
        getLocalUsageSummary(30),
      ]);

      if (cancelled) return;

      if (balanceResult.status === "fulfilled") {
        setLocalBalance(balanceResult.value);
      } else {
        console.warn("[Nova] Failed to load local trial balance:", balanceResult.reason);
      }

      if (usageResult.status === "fulfilled") {
        setLocalUsage(usageResult.value);
      } else {
        console.warn("[Nova] Failed to load local trial usage:", usageResult.reason);
      }
    };
    load();

    const onLocalCreditsChanged = () => load();
    window.addEventListener("nova-local-credits-changed", onLocalCreditsChanged);
    return () => {
      cancelled = true;
      window.removeEventListener("nova-local-credits-changed", onLocalCreditsChanged);
    };
  }, [isAuthenticated, isAuthConfigured]);

  if (!isAuthenticated) {
    const localBalanceCents = localBalance?.balance_cents ?? 0;
    const trialExhausted = localBalanceCents <= 0;

    const handleOAuthSignIn = async (provider: "google" | "discord") => {
      setAuthError(null);
      setAuthNotice(null);
      setAuthLoading(provider);
      try {
        if (provider === "google") {
          await signInWithGoogle();
        } else {
          await signInWithDiscord();
        }
      } catch (err) {
        console.error("Billing OAuth sign in failed:", err);
        setAuthError("Failed to start sign in. Please try again.");
      } finally {
        setAuthLoading(null);
      }
    };

    const handleEmailAuthSubmit = async (event: React.FormEvent<HTMLFormElement>) => {
      event.preventDefault();
      if (!authEmail || !authPassword) return;

      const loadingState = emailAuthMode === "signup" ? "email-signup" : "email-signin";
      setAuthError(null);
      setAuthNotice(null);
      setAuthLoading(loadingState);

      try {
        if (emailAuthMode === "signup") {
          await signUpWithEmail(authEmail, authPassword);
          setAuthNotice("Check your email to confirm your account, then sign in.");
        } else {
          await signInWithEmail(authEmail, authPassword);
        }
      } catch (err: any) {
        console.error("Billing email auth failed:", err);
        setAuthError(err?.message || "Authentication failed. Please try again.");
      } finally {
        setAuthLoading(null);
      }
    };

    return (
      <div className="p-6 h-full flex flex-col">
        <div className="mb-4">
          <h1 className="text-xl font-semibold" style={{ color: "var(--text-primary)" }}>
            Billing
          </h1>
          <p className="text-sm" style={{ color: "var(--text-tertiary)" }}>
            Free trial credits
          </p>
        </div>
        <div className="flex-1 overflow-auto">
          <div className="max-w-3xl mx-auto py-8 px-4">
            <div className="bg-white border border-[var(--border-subtle)] rounded-xl shadow-sm p-6 mb-6">
              <p className="text-xs uppercase tracking-wide text-[var(--text-tertiary)] mb-2">
                Remaining Free Credits
              </p>
              <p className="text-3xl font-semibold text-[var(--text-primary)]">
                ${localBalance?.balance_dollars || "0.00"}
              </p>
              <p className="text-sm text-[var(--text-secondary)] mt-2">
                You can use free trial credits without signing in. Billing starts only after sign-in.
              </p>
            </div>

            <div className="bg-white border border-[var(--border-subtle)] rounded-xl shadow-sm p-6 mb-6">
              <p className="text-xs uppercase tracking-wide text-[var(--text-tertiary)] mb-3">
                Trial Usage (30 Days)
              </p>
              <div className="grid grid-cols-2 gap-4">
                <div>
                  <p className="text-2xl font-semibold text-[var(--text-primary)]">
                    {localUsage?.total_requests || 0}
                  </p>
                  <p className="text-xs text-[var(--text-secondary)]">Requests</p>
                </div>
                <div>
                  <p className="text-2xl font-semibold text-[var(--text-primary)]">
                    ${localUsage?.total_cost_dollars || "0.00"}
                  </p>
                  <p className="text-xs text-[var(--text-secondary)]">Estimated Cost</p>
                </div>
              </div>
            </div>

            <div className="bg-white border border-[var(--border-subtle)] rounded-xl shadow-sm p-6">
              <p className="text-xs uppercase tracking-wide text-[var(--text-tertiary)] mb-2">
                Add More Credits
              </p>
              <p className="text-sm text-[var(--text-secondary)] mb-4">
                {!isAuthConfigured
                  ? "Cloud billing is not configured in this build. Use local provider keys in Settings."
                  : trialExhausted
                    ? "Sign in to continue and add paid credits with Stripe."
                    : "Sign in anytime to transfer your remaining free credits to your account, then add more with Stripe."}
              </p>
              {isAuthConfigured ? (
                <div className="space-y-3">
                  {authError ? (
                    <div className="rounded-xl border border-red-200 bg-red-50 px-3 py-2 text-xs text-red-700 text-center">
                      {authError}
                    </div>
                  ) : null}
                  {authNotice ? (
                    <div className="rounded-xl border border-emerald-200 bg-emerald-50 px-3 py-2 text-xs text-emerald-700 text-center">
                      {authNotice}
                    </div>
                  ) : null}
                  <button
                    onClick={() => handleOAuthSignIn("google")}
                    disabled={authLoading !== null}
                    className="w-full flex items-center justify-center gap-3 px-4 py-3 bg-white hover:bg-gray-50 text-gray-700 font-medium rounded-2xl border border-gray-200 transition-all hover:border-gray-300 active:scale-95 duration-200 disabled:opacity-50"
                  >
                    <GoogleIcon className="w-5 h-5" />
                    <span>{authLoading === "google" ? "Opening Google..." : "Continue with Google"}</span>
                  </button>
                  <button
                    onClick={() => handleOAuthSignIn("discord")}
                    disabled={authLoading !== null}
                    className="w-full flex items-center justify-center gap-3 px-4 py-3 bg-[#5865F2] hover:bg-[#4752C4] text-white font-medium rounded-2xl transition-all shadow-md hover:shadow-lg active:scale-95 duration-200 disabled:opacity-50"
                  >
                    <DiscordIcon className="w-5 h-5" />
                    <span>{authLoading === "discord" ? "Opening Discord..." : "Continue with Discord"}</span>
                  </button>
                  <button
                    onClick={() => {
                      setShowEmailAuth((prev) => !prev);
                      setAuthError(null);
                      setAuthNotice(null);
                    }}
                    disabled={authLoading !== null}
                    className="w-full flex items-center justify-center gap-3 px-4 py-3 bg-gray-50 hover:bg-gray-100 text-gray-900 font-medium rounded-2xl transition-all active:scale-95 duration-200 disabled:opacity-50"
                  >
                    <Mail className="w-5 h-5 text-gray-500" />
                    <span>Continue with Email</span>
                  </button>
                  {showEmailAuth ? (
                    <form onSubmit={handleEmailAuthSubmit} className="space-y-3 rounded-2xl bg-gray-50 p-4">
                      <input
                        type="email"
                        value={authEmail}
                        onChange={(event) => setAuthEmail(event.target.value)}
                        placeholder="name@example.com"
                        className="w-full px-4 py-3 rounded-xl bg-white border border-gray-200 focus:ring-2 focus:ring-black/5 focus:outline-none text-gray-900 placeholder:text-gray-400 text-sm transition-all"
                        required
                      />
                      <input
                        type="password"
                        value={authPassword}
                        onChange={(event) => setAuthPassword(event.target.value)}
                        placeholder={emailAuthMode === "signup" ? "Create password" : "Password"}
                        className="w-full px-4 py-3 rounded-xl bg-white border border-gray-200 focus:ring-2 focus:ring-black/5 focus:outline-none text-gray-900 placeholder:text-gray-400 text-sm transition-all"
                        required
                        minLength={emailAuthMode === "signup" ? 8 : undefined}
                      />
                      <div className="flex items-center gap-2">
                        <button
                          type="submit"
                          disabled={authLoading !== null}
                          className="px-4 py-2.5 rounded-xl bg-black hover:bg-gray-800 text-white text-xs font-semibold transition-all disabled:opacity-50"
                        >
                          {emailAuthMode === "signup"
                            ? authLoading === "email-signup"
                              ? "Creating..."
                              : "Create account"
                            : authLoading === "email-signin"
                              ? "Signing in..."
                              : "Sign in"}
                        </button>
                        <button
                          type="button"
                          onClick={() => {
                            setEmailAuthMode((prev) => (prev === "signup" ? "signin" : "signup"));
                            setAuthError(null);
                            setAuthNotice(null);
                          }}
                          className="text-xs text-gray-500 hover:text-gray-700 transition-colors"
                        >
                          {emailAuthMode === "signup"
                            ? "Have an account? Sign in"
                            : "Need an account? Sign up"}
                        </button>
                      </div>
                    </form>
                  ) : null}
                </div>
              ) : null}
            </div>
          </div>
        </div>
      </div>
    );
  }

  return (
    <div className="p-6 h-full flex flex-col">
      <div className="mb-4">
        <h1 className="text-xl font-semibold" style={{ color: "var(--text-primary)" }}>
          Billing
        </h1>
        <p className="text-sm" style={{ color: "var(--text-tertiary)" }}>
          Credits, usage, and payments
        </p>
      </div>
      <div className="flex-1 overflow-auto">
        <Billing />
      </div>
    </div>
  );
}
