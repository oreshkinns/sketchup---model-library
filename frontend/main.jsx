import React from "react";
import { createRoot } from "react-dom/client";
import { flushSync } from "react-dom";
import App from "./App.jsx";
import { initializeRuntime } from "./runtime.jsx";

flushSync(() => createRoot(document.getElementById("root")).render(<App />));
initializeRuntime();
