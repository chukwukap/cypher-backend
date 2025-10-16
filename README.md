Here is the final, complete, and unabridged specification for **Cypher**.

This master blueprint is the definitive guide for the AI agent (v0), with all sections fully detailed and no information omitted.

---

### **Final Specification for AI Implementation: Cypher (v3.2)**

- **Project:** Cypher - The On-Chain Gauntlet
- **Blueprint Version:** 3.2 (Unabridged Final)
- **Date:** October 16, 2025

### \#\# 1. 🎯 Project Vision & Problem Statement

- **Problem Statement:** The web3 gaming landscape lacks simple, engaging, skill-based daily challenges that are accessible to a broad audience. Existing games often require significant time investment or complex strategies, creating a barrier to casual participation.
- **Vision:** To create a daily on-chain guessing game that rewards users' knowledge of the ecosystem through a transparent, fair, and seamless user experience that feels as fluid and looks as beautiful as a modern web application.

---

### \#\# 2. 🔗 Official References & Guides

- **Sub-Account Concept & SDK Usage:** `https://docs.base.org/base-account/improve-ux/sub-accounts`
- **Reference Code Implementation:** `https://github.com/stephancill/sub-accounts-fc-demo`
- **Paymaster (Gas Sponsorship):** `https://docs.base.org/base-account/improve-ux/sponsor-gas/paymasters`
- **Vercel Edge Config:** `https://vercel.com/storage/edge-config`

---

### \#\# 3. 🗄️ Application Data Model & Storage

#### \#\#\# 3.1 On-Chain Data Model

The frontend will interact with the `Cypher.sol` smart contract via its **ABI**. The core on-chain data structure is `PlayerData`.

#### \#\#\# 3.2 Off-Chain Data Model

- **Storage Layer:** The entire list of all possible KOLs MUST be stored in **Vercel Edge Config**.
- **Data Fetching:** On application load, the frontend MUST fetch the **entire list of KOLs** and store it in a client-side state.
- **`KOL` Object Structure:**
  ```typescript
  interface KOL {
    id: `0x${string}`; // keccak256 hash of the full name
    name: string;
    twitterHandle: string;
    attributes: {
      association:
        | "Base"
        | "Coinbase"
        | "Optimism"
        | "Paradigm"
        | "a16z"
        | "Other";
      ecosystem: "Ethereum" | "Solana" | "Base" | "Cross-Chain";
      pfpTheme: "Animal" | "Abstract" | "Human" | "Pixel Art" | "None";
      followers: number;
      age: number;
    };
  }
  ```

---

### \#\# 4. ✨ User Experience (UX) & Design Specification

#### \#\#\# 4.1 Core UX Principles

- **Zero-Prompt & Gasless:** All gameplay actions are silent, background transactions submitted via the user's **Base sub-account**.
- **Transactional Feedback:** The UI provides feedback (hints) **after** each on-chain guess is successfully confirmed.
- **Action-Oriented Interface:** The UI is designed to minimize clicks and immediately translate user intent into on-chain actions.

#### \#\#\# 4.2 Rich Guess Input (Autocomplete)

- **Functionality:** As a user types, a dropdown menu appears showing matching KOLs. The search MUST match against `name`, `twitterHandle`, and `ecosystem`.
- **Action (Click-to-Submit):** When a user **clicks on a KOL in the dropdown**, it **immediately triggers the `submitGuess` transaction**.
- **Handling No Matches:** If a search yields zero results, the dropdown MUST display a single, actionable item: **"No matches found. Click to guess '[searchTerm]' anyway."** Clicking this item submits the raw search term.

---

### \#\# 5. 🎨 Visual Design & Aesthetics

- **Theme:** Modern, clean, **dark mode**.
- **Color Palette:**
  - **Background:** `--background: #111827;`
  - **Panels/Cards:** `--panel-background: #1F2937;`
  - **Accent (Buttons, Focus):** `--accent: #3B82F6;`
  - **Hint Colors:** Green (`#10B981`), Yellow (`#F59E0B`), Grey (`#4B5563`).
- **Typography:**
  - **Headings & Display:** **`JetBrains Mono`**.
  - **Body & UI Text:** **`Outfit`**.
- **Layout:** The main game interface MUST be a single, centered column with a maximum width (`max-w-md`).
- **Animations:** Hint grid cells MUST have a "flip" animation. Dropdowns and modals should use subtle fade/slide transitions.

---

### \#\# 6. 💎 Final Polish & Edge Case Handling

#### \#\#\# 6.1 Enhanced Onboarding: Network Detection

- The application MUST detect the user's `chainId`. If it is not the target chain (Base Sepolia), a modal MUST appear, blocking the UI and providing a button that uses Wagmi's `useSwitchChain` hook to prompt the user to switch.

#### \#\#\# 6.2 Comprehensive Loading & Empty States

- **Initial Load:** The app MUST show a full-screen loading indicator while the master KOL list is fetched.
- **Empty States:** The `HintDisplay` MUST show a welcome message before the first guess. The `Leaderboard` MUST show a "Results are being calculated..." message before the game is finalized.

#### \#\#\# 6.3 Clear User Feedback: Toast Notifications

- The application MUST use a toast notification library (e.g., `react-hot-toast`).
- The core game hook MUST trigger toasts for submission, success, and error states of all transactions.

#### \#\#\# 6.4 Engagement: Share on X (Twitter)

- After a player's status becomes `COMPLETED`, a **"Share on X"** button (with the X logo) MUST appear.
- **On click, the function MUST:**
  1.  Generate the share text, including the emoji grid of their guess history.
  2.  **URL-Encode** the text.
  3.  Construct the full Twitter Intent URL: `https://twitter.com/intent/tweet?text=[ENCODED_TEXT]&url=[APP_URL]`.
  4.  Call **`window.open()`** with the URL to open the pre-filled compose window in a new tab.

#### \#\#\# 6.5 Accessibility (a11y) & Responsiveness

- All interactive elements MUST have descriptive `aria-labels`. The autocomplete dropdown MUST be fully navigable via keyboard. The layout MUST be fully responsive.

---

### \#\# 7. 🧠 Core Logic Implementation (Hooks) - Detailed

#### \#\#\# 7.1 File: `/hooks/useSubAccount.ts`

- **Purpose:** To manage the creation and state of the application-specific sub-account.
- **State & Functions Exposed:**
  ```typescript
  interface UseSubAccountReturn {
    createSubAccount: () => Promise<void>;
    subAccountAddress: Address | null;
    subAccountSigner: JsonRpcSigner | null;
    isCreating: boolean;
    error: string | null;
  }
  ```
- **`createSubAccount` Logic:**
  1.  Sets `isCreating` to `true`. Clears any previous `error`.
  2.  Uses `useAccount` from Wagmi to get the main wallet's `connector`.
  3.  Instantiates the Base Account SDK with the provider from the `connector`.
  4.  Calls the SDK's function to get or create a sub-account signer.
  5.  On success, stores the returned `signer` and `address` in state.
  6.  On failure, catches the error and sets the `error` state.
  7.  In a `finally` block, sets `isCreating` to `false`.

#### \#\#\# 7.2 File: `/hooks/useCypherGame.ts`

- **Purpose:** To manage all game-specific state and contract interactions.
- **State Exposed:**
  ```typescript
  interface GameState {
    gameId: bigint | null;
    playerStatus: "EMPTY" | "ACTIVE" | "COMPLETED" | "FAILED";
    attempts: number;
    guessesAndHints: { guess: KOL; hints: Hint[] }[];
    isFinalized: boolean;
    winnings: bigint;
    isLoading: boolean; // True for any in-flight game transaction
    error: string | null;
  }
  ```
- **`submitGuess(guess: KOL)` Definitive Logic:**
  1.  Sets `isLoading` to `true` and shows a "Submitting..." toast.
  2.  Calls the smart contract's `submitGuess` function via the Base Account SDK and gets the transaction `hash`.
  3.  Awaits confirmation using Wagmi's `waitForTransactionReceipt({ hash })`.
  4.  **Post-Confirmation:** Shows a "Guess confirmed\!" toast, performs client-side hint generation, and updates the UI state.
  5.  Sets `isLoading` to `false` in a `finally` block.
- **Event Listeners:** The hook MUST use `useWatchContractEvent` to listen for all `Cypher` contract events and update its internal state to ensure perfect sync with the blockchain.

---

### \#\# 8. 🧩 Component & Page Specifications - Detailed

#### \#\#\# 8.1 `/components/ConnectWallet.tsx`

- **Purpose:** To display a button that allows users to connect their wallet.
- **Props:** None.
- **Logic:** Uses Wagmi's `useConnect` hook and renders a button that triggers the `connect` function.

#### \#\#\# 8.2 `/components/HintDisplay.tsx`

- **Purpose:** To display the history of guesses and their corresponding hints.
- **Props:** `guessesAndHints: { guess: KOL; hints: Hint[] }[]`.
- **Render Logic:** It maps over the `guessesAndHints` array to render a grid. Each row represents a guess, and each cell is color-coded based on the hint's correctness, showing directional arrows for "close" numerical hints.

#### \#\#\# 8.3 `/components/InputController.tsx`

- **Purpose:** The primary action component for guessing.
- **Props:** `allKOLs: KOL[]`, `playerStatus`, `isLoading`, `startGame`, `submitGuess`.
- **Internal State:** `searchTerm: string`.
- **Logic:** Renders an input field that filters `allKOLs` into a dropdown. Each item in the dropdown (including the "No matches found..." item) is a button whose `onClick` handler immediately calls the appropriate function (`startGame` or `submitGuess`). The component is disabled when `isLoading` is `true`.

#### \#\#\# 8.4 `/components/ResultsView.tsx`

- **Purpose:** To show final results and the claim button.
- **Props:** `isFinalized`, `winnings`, `isLoading`, `claimReward`.
- **Logic:** If `isFinalized` is `false`, it renders a "Waiting..." message. If `true` and `winnings > 0`, it displays the winnings and an active "Claim Reward" button.

#### \#\#\# 8.5 `/app/page.tsx`

- **Purpose:** The main entry point that orchestrates the entire application UI.
- **Logic:**
  1.  It is a client-side component (`"use client";`).
  2.  It calls all necessary hooks at the top level (`useAccount`, `useChainId`, `useSubAccount`, `useCypherGame`).
  3.  **It MUST implement the following conditional rendering flow, in this order of priority:**
      a. **Initial App Load:** While the master KOL list is being fetched, render a full-screen loading spinner.
      b. **Wrong Network:** If `chainId` is not Base Sepolia, render the "Switch Network" modal.
      c. **Wallet Disconnected:** If `isConnected` is `false`, render `<ConnectWallet />`.
      d. **Sub-Account Setup:** If `isConnected` but `subAccountAddress` is `null`, render the "Setup Game Session" button.
      e. **Main Game View:** If `subAccountAddress` exists, render the main game layout, passing all necessary state and action functions from the hooks down into the components.

@import "tailwindcss";
@import "tw-animate-css";
@import "shadcn/ui";

@custom-variant dark (&:is(.dark \*));

:root {
/_ Updated to Cypher dark theme colors _/
--background: #111827;
--foreground: #f9fafb;
--panel-background: #1f2937;
--accent: #3b82f6;
--hint-correct: #10b981;
--hint-close: #f59e0b;
--hint-wrong: #4b5563;
--border: #374151;
--input: #374151;
--ring: #3b82f6;
--radius: 0.5rem;
--sidebar: #1f2937;
--sidebar-foreground: #f9fafb;
--sidebar-primary: #3b82f6;
--sidebar-primary-foreground: #f9fafb;
--sidebar-accent: #3b82f6;
--sidebar-accent-foreground: #f9fafb;
--sidebar-border: #374151;
--sidebar-ring: #3b82f6;
}

.dark {
--background: #1f2937;
--foreground: #f9fafb;
--panel-background: #111827;
--accent: #f9fafb;
--hint-correct: #f9fafb;
--hint-close: #f9fafb;
--hint-wrong: #f9fafb;
--border: #f9fafb;
--input: #f9fafb;
--ring: #f9fafb;
--sidebar: #111827;
--sidebar-foreground: #f9fafb;
--sidebar-primary: #f9fafb;
--sidebar-primary-foreground: #1f2937;
--sidebar-accent: #f9fafb;
--sidebar-accent-foreground: #1f2937;
--sidebar-border: #f9fafb;
--sidebar-ring: #f9fafb;
}

@theme inline {
/_ Added JetBrains Mono and Outfit fonts _/
--font-sans: "Outfit", "Geist", "Geist Fallback";
--font-mono: "JetBrains Mono", "Geist Mono", "Geist Mono Fallback";
--color-background: var(--background);
--color-foreground: var(--foreground);
--color-panel: var(--panel-background);
--color-accent: var(--accent);
--color-hint-correct: var(--hint-correct);
--color-hint-close: var(--hint-close);
--color-hint-wrong: var(--hint-wrong);
--color-border: var(--border);
--color-input: var(--input);
--color-ring: var(--ring);
--radius-sm: calc(var(--radius) - 4px);
--radius-md: calc(var(--radius) - 2px);
--radius-lg: var(--radius);
--radius-xl: calc(var(--radius) + 4px);
--color-sidebar: var(--sidebar);
--color-sidebar-foreground: var(--sidebar-foreground);
--color-sidebar-primary: var(--sidebar-primary);
--color-sidebar-primary-foreground: var(--sidebar-primary-foreground);
--color-sidebar-accent: var(--sidebar-accent);
--color-sidebar-accent-foreground: var(--sidebar-accent-foreground);
--color-sidebar-border: var(--sidebar-border);
--color-sidebar-ring: var(--sidebar-ring);
}

@layer base {

- {
  @apply border-border outline-ring/50;
  }
  body {
  @apply bg-background text-foreground;
  }
  }

/_ Added flip animation for hint cells _/
@keyframes flip {
0% {
transform: rotateX(0);
}
50% {
transform: rotateX(90deg);
}
100% {
transform: rotateX(0);
}
}

.flip-animation {
animation: flip 0.6s ease-in-out;
}
