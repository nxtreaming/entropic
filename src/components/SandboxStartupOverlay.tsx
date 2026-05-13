import { CheckCircle2, Loader2 } from "lucide-react";
import {
  StartupUseCaseCard,
  useSmoothStartupUseCase,
} from "./StartupUseCaseCard";

export type GatewayStartupStage = "idle" | "credits" | "token" | "launch" | "health" | "connect";

type StartupAction = {
  label: string;
  onClick: () => void;
};

type StartupError = {
  message: string;
  actions?: StartupAction[];
};

type Props = {
  stage: GatewayStartupStage;
  retryIn?: number | null;
  factIndex?: number;
  startupError?: StartupError | null;
  showFirstTimeHint?: boolean;
  className?: string;
};

export function SandboxStartupOverlay({
  stage,
  retryIn = null,
  factIndex = 0,
  startupError = null,
  showFirstTimeHint = false,
  className = "absolute inset-0 z-50",
}: Props) {
  const {
    isSwitching: promptIsSwitching,
    useCase,
  } = useSmoothStartupUseCase(factIndex);

  return (
    <div className={`${className} flex items-center justify-center`}>
      <div className="w-full max-w-sm mx-4 rounded-2xl bg-[var(--bg-card)] border border-[var(--border-subtle)] shadow-xl p-6">
        <StartupUseCaseCard
          isSwitching={promptIsSwitching}
          useCase={useCase}
        />

        <div className="mt-6 pt-4 border-t border-[var(--border-subtle)]">
          <div className="flex items-center justify-between text-[10px] text-[var(--text-tertiary)] uppercase tracking-widest font-semibold mb-3">
            System Status
            {stage === "connect" ? (
              <span className="text-green-500">Finalizing</span>
            ) : stage === "health" ? (
              <span className="text-green-500">Ready</span>
            ) : (
              <span className="animate-pulse">Initializing...</span>
            )}
          </div>
          <div className="space-y-2.5">
            <div className="flex items-center gap-2.5 text-[11px] text-[var(--text-secondary)]">
              {stage === "credits" || stage === "token" ? (
                <Loader2 className="w-3.5 h-3.5 animate-spin text-violet-500" />
              ) : stage === "launch" || stage === "health" ? (
                <CheckCircle2 className="w-3.5 h-3.5 text-green-500" />
              ) : (
                <div className="w-3.5 h-3.5 rounded-full border border-[var(--border-subtle)]" />
              )}
              <span className={stage === "credits" || stage === "token" ? "font-medium text-[var(--text-primary)]" : ""}>
                Getting things ready
              </span>
            </div>
            <div className="flex items-center gap-2.5 text-[11px] text-[var(--text-secondary)]">
              {stage === "launch" ? (
                <Loader2 className="w-3.5 h-3.5 animate-spin text-violet-500" />
              ) : stage === "health" || stage === "connect" ? (
                <CheckCircle2 className="w-3.5 h-3.5 text-green-500" />
              ) : (
                <div className="w-3.5 h-3.5 rounded-full border border-[var(--border-subtle)]" />
              )}
              <span className={stage === "launch" ? "font-medium text-[var(--text-primary)]" : ""}>
                Starting sandbox
              </span>
            </div>
            <div className="flex items-center gap-2.5 text-[11px] text-[var(--text-secondary)]">
              {stage === "health" ? (
                <Loader2 className="w-3.5 h-3.5 animate-spin text-violet-500" />
              ) : stage === "connect" ? (
                <CheckCircle2 className="w-3.5 h-3.5 text-green-500" />
              ) : (
                <div className="w-3.5 h-3.5 rounded-full border border-[var(--border-subtle)]" />
              )}
              <span className={stage === "health" ? "font-medium text-[var(--text-primary)]" : ""}>
                Checking connection
              </span>
            </div>
            <div className="flex items-center gap-2.5 text-[11px] text-[var(--text-secondary)]">
              {stage === "connect" ? (
                <Loader2 className="w-3.5 h-3.5 animate-spin text-violet-500" />
              ) : (
                <div className="w-3.5 h-3.5 rounded-full border border-[var(--border-subtle)]" />
              )}
              <span className={stage === "connect" ? "font-medium text-[var(--text-primary)]" : ""}>
                Opening Entropic
              </span>
            </div>
          </div>
        </div>

        {showFirstTimeHint && !retryIn && (
          <div className="mt-4 text-[10px] text-[var(--text-tertiary)] text-center italic">
            First-time setup may take a few seconds.
          </div>
        )}

        {startupError && (
          <div className="mt-3 text-xs text-red-500">
            {startupError.message}
            {startupError.actions && startupError.actions.length > 0 && (
              <div className="mt-3 flex flex-wrap gap-2">
                {startupError.actions.map((action) => (
                  <button
                    key={action.label}
                    className="rounded-full border border-[var(--border-subtle)] bg-[var(--bg-card)] px-3 py-1 text-xs text-[var(--text-primary)] hover:bg-[var(--bg-muted)]"
                    onClick={action.onClick}
                  >
                    {action.label}
                  </button>
                ))}
              </div>
            )}
          </div>
        )}
      </div>
    </div>
  );
}
