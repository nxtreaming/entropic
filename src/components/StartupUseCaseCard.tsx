import { useEffect, useState } from "react";
import {
  BookOpen,
  CalendarCheck,
  Code2,
  FileText,
  FolderOpen,
  Globe2,
  Image,
  ListChecks,
  MailCheck,
  Table2,
  type LucideIcon,
} from "lucide-react";
import {
  getStartupUseCase,
  STARTUP_USE_CASES,
  type StartupUseCase,
} from "../lib/startupUseCases";

const USE_CASE_ICONS: Record<string, LucideIcon> = {
  Browser: Globe2,
  Code: Code2,
  Email: MailCheck,
  Files: FolderOpen,
  Memory: BookOpen,
  Notes: FileText,
  Schedule: CalendarCheck,
  Screenshot: Image,
  Sheets: Table2,
  Tasks: ListChecks,
};

export function useSmoothStartupUseCase(factIndex: number) {
  const [visibleFactIndex, setVisibleFactIndex] = useState(factIndex);
  const [isSwitching, setIsSwitching] = useState(false);

  useEffect(() => {
    const nextIndex =
      ((factIndex % STARTUP_USE_CASES.length) + STARTUP_USE_CASES.length) %
      STARTUP_USE_CASES.length;
    const currentIndex =
      ((visibleFactIndex % STARTUP_USE_CASES.length) + STARTUP_USE_CASES.length) %
      STARTUP_USE_CASES.length;
    if (nextIndex === currentIndex) {
      return;
    }

    setIsSwitching(true);
    const timeout = window.setTimeout(() => {
      setVisibleFactIndex(factIndex);
      window.requestAnimationFrame(() => setIsSwitching(false));
    }, 220);

    return () => window.clearTimeout(timeout);
  }, [factIndex, visibleFactIndex]);

  const activeIndex =
    ((visibleFactIndex % STARTUP_USE_CASES.length) + STARTUP_USE_CASES.length) %
    STARTUP_USE_CASES.length;

  return {
    activeIndex,
    isSwitching,
    useCase: getStartupUseCase(visibleFactIndex),
  };
}

type Props = {
  className?: string;
  isSwitching: boolean;
  useCase: StartupUseCase;
};

export function StartupUseCaseCard({ className = "", isSwitching, useCase }: Props) {
  const Icon = USE_CASE_ICONS[useCase.label] ?? ListChecks;

  return (
    <div
      className={`${className} h-[172px] rounded-xl border border-violet-500/20 bg-gradient-to-b from-violet-500/10 to-violet-500/5 p-4 transition-all duration-500 ease-out will-change-transform ${
        isSwitching ? "translate-y-1 opacity-0" : "translate-y-0 opacity-100"
      }`}
    >
      <p className="text-center text-[10px] font-bold uppercase text-violet-500">
        Ask Entropic about
      </p>
      <div className="mt-2 flex justify-center">
        <span className="inline-flex min-h-7 items-center gap-1.5 rounded-full border border-violet-500/20 bg-[var(--bg-card)] px-3 py-1 text-xs font-semibold text-violet-500 shadow-sm">
          <Icon className="h-3.5 w-3.5" />
          {useCase.label}
        </span>
      </div>

      <div className="mt-4 rounded-lg border border-[var(--border-subtle)] bg-[var(--bg-card)] p-3 shadow-sm">
        <p className="text-center text-sm font-medium leading-relaxed text-[var(--text-primary)]">
          &quot;{useCase.prompt}&quot;
        </p>
      </div>
    </div>
  );
}
