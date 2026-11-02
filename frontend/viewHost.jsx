import React from "react";
import { createRoot } from "react-dom/client";
import { flushSync } from "react-dom";

// The SketchUp bridge is synchronous. Flush each view before controller code
// reads its DOM, focuses an element, or installs delegated event listeners.
const views = new Map();
export function mountView(container, children) {
  for (const [element, root] of views) {
    if (element !== container && container.contains(element)) {
      flushSync(() => root.unmount());
      views.delete(element);
    }
  }
  let root = views.get(container);
  if (!root) {
    root = createRoot(container);
    views.set(container, root);
  }
  flushSync(() => root.render(<React.Fragment>{children}</React.Fragment>));
  // These hosts replace a complete option list. Preserve the original dialog
  // semantics: each freshly populated action starts with its first option.
  // Filters restore their saved value explicitly after mounting their options.
  if (container.tagName === "SELECT") container.selectedIndex = 0;
}
export function viewList(items) {
  return items.length ? items : "";
}
