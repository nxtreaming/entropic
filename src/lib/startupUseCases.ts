export type StartupUseCase = {
  label: string;
  title: string;
  prompt: string;
};

export const STARTUP_USE_CASES: StartupUseCase[] = [
  {
    label: "Files",
    title: "Clean up a messy folder",
    prompt: "Find the important files in this folder and summarize them.",
  },
  {
    label: "Notes",
    title: "Turn notes into a checklist",
    prompt: "Turn these rough notes into simple next steps.",
  },
  {
    label: "Browser",
    title: "Compare a few options",
    prompt: "Compare these pages and tell me which one fits best.",
  },
  {
    label: "Sheets",
    title: "Understand a spreadsheet",
    prompt: "Tell me what changed and what looks off.",
  },
  {
    label: "Email",
    title: "Draft a clear reply",
    prompt: "Write a short, polite reply asking for the missing date.",
  },
  {
    label: "Schedule",
    title: "Plan a busy day",
    prompt: "Look at my day and tell me what needs attention first.",
  },
  {
    label: "Code",
    title: "Plan work from a repo",
    prompt: "Read this project and tell me which files matter.",
  },
  {
    label: "Screenshot",
    title: "Explain a screenshot",
    prompt: "Tell me what this screenshot shows and what to fix.",
  },
  {
    label: "Memory",
    title: "Remember project context",
    prompt: "Make a simple project brief and list open questions.",
  },
  {
    label: "Tasks",
    title: "Break down a vague task",
    prompt: "Help me turn this into something I can do this afternoon.",
  },
];

export function getStartupUseCase(index: number): StartupUseCase {
  const safeIndex = ((index % STARTUP_USE_CASES.length) + STARTUP_USE_CASES.length) %
    STARTUP_USE_CASES.length;
  return STARTUP_USE_CASES[safeIndex];
}
