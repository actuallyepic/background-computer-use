import Foundation

enum BrowserBootstrapScript {
    static let source = """
(() => {
  const existing = window.__bcu;
  if (existing && existing.version === 1) {
    return;
  }

  const weakIDs = new WeakMap();
  const ids = new Map();
  let nextID = 1;

  function nodeID(element) {
    if (!element || element.nodeType !== Node.ELEMENT_NODE) {
      return null;
    }
    let id = weakIDs.get(element);
    if (!id) {
      id = "bnode_" + nextID++;
      weakIDs.set(element, id);
      ids.set(id, element);
    }
    return id;
  }

  function textOf(element) {
    const value = element.innerText || element.textContent || element.getAttribute("aria-label") || element.getAttribute("title") || "";
    return String(value).replace(/\\s+/g, " ").trim().slice(0, 500);
  }

  function valuePreview(element) {
    if (element && "value" in element) {
      return String(element.value || "").slice(0, 500);
    }
    return null;
  }

  function accessibleName(element) {
    return (
      element.getAttribute("aria-label") ||
      element.getAttribute("title") ||
      element.getAttribute("placeholder") ||
      textOf(element) ||
      null
    );
  }

  function roleOf(element) {
    const explicit = element.getAttribute("role");
    if (explicit) return explicit;
    const tag = element.tagName.toLowerCase();
    if (tag === "a") return "link";
    if (tag === "button") return "button";
    if (tag === "input") {
      const type = (element.getAttribute("type") || "text").toLowerCase();
      if (type === "checkbox") return "checkbox";
      if (type === "radio") return "radio";
      if (type === "submit" || type === "button") return "button";
      return "textbox";
    }
    if (tag === "textarea") return "textbox";
    if (tag === "select") return "combobox";
    if (element.isContentEditable) return "textbox";
    return tag;
  }

  function isEditable(element) {
    if (!element) return false;
    const tag = element.tagName.toLowerCase();
    return element.isContentEditable || tag === "textarea" || (tag === "input" && !["button", "submit", "checkbox", "radio", "range", "color", "file"].includes((element.type || "").toLowerCase()));
  }

  function isEnabled(element) {
    return !element.disabled && element.getAttribute("aria-disabled") !== "true";
  }

  function isVisible(element) {
    if (!element || element.nodeType !== Node.ELEMENT_NODE) return false;
    const style = window.getComputedStyle(element);
    if (style.display === "none" || style.visibility === "hidden" || Number(style.opacity) === 0) return false;
    const rect = element.getBoundingClientRect();
    if (rect.width <= 0 || rect.height <= 0) return false;
    if (rect.bottom < 0 || rect.right < 0 || rect.top > window.innerHeight || rect.left > window.innerWidth) return false;
    return true;
  }

  function cssPath(element) {
    if (!element || element.nodeType !== Node.ELEMENT_NODE) return null;
    if (element.id) return "#" + CSS.escape(element.id);
    const parts = [];
    let node = element;
    while (node && node.nodeType === Node.ELEMENT_NODE && parts.length < 5) {
      let part = node.tagName.toLowerCase();
      if (node.classList && node.classList.length > 0) {
        part += "." + Array.from(node.classList).slice(0, 2).map(CSS.escape).join(".");
      }
      const parent = node.parentElement;
      if (parent) {
        const siblings = Array.from(parent.children).filter(child => child.tagName === node.tagName);
        if (siblings.length > 1) {
          part += ":nth-of-type(" + (siblings.indexOf(node) + 1) + ")";
        }
      }
      parts.unshift(part);
      node = parent;
    }
    return parts.join(" > ");
  }

  function selectorCandidates(element) {
    const candidates = [];
    if (element.id) candidates.push("#" + CSS.escape(element.id));
    const aria = element.getAttribute("aria-label");
    if (aria) candidates.push(element.tagName.toLowerCase() + "[aria-label=" + JSON.stringify(aria) + "]");
    const name = element.getAttribute("name");
    if (name) candidates.push(element.tagName.toLowerCase() + "[name=" + JSON.stringify(name) + "]");
    const path = cssPath(element);
    if (path) candidates.push(path);
    return [...new Set(candidates)].slice(0, 5);
  }

  function rectObject(rect) {
    return {
      x: rect.left,
      y: rect.top,
      width: rect.width,
      height: rect.height
    };
  }

  function pointObject(rect) {
    return {
      x: rect.left + rect.width / 2,
      y: rect.top + rect.height / 2
    };
  }

  function serializeElement(element, displayIndex) {
    const rect = element.getBoundingClientRect();
    return {
      displayIndex,
      nodeID: nodeID(element),
      role: roleOf(element),
      tagName: element.tagName.toLowerCase(),
      text: textOf(element) || null,
      accessibleName: accessibleName(element),
      valuePreview: valuePreview(element),
      selectorCandidates: selectorCandidates(element),
      rectViewport: rectObject(rect),
      centerViewport: pointObject(rect),
      rectAppKit: null,
      centerAppKit: null,
      isVisible: isVisible(element),
      isEnabled: isEnabled(element),
      isEditable: isEditable(element)
    };
  }

  function interactableElements() {
    const selector = [
      "a[href]",
      "button",
      "input",
      "textarea",
      "select",
      "[contenteditable='true']",
      "[role='button']",
      "[role='link']",
      "[role='textbox']",
      "[role='checkbox']",
      "[role='radio']",
      "[role='menuitem']",
      "[tabindex]"
    ].join(",");
    return Array.from(document.querySelectorAll(selector))
      .filter(isVisible)
      .filter(element => isEnabled(element));
  }

  function snapshot(maxElements, includeRawText) {
    const elements = interactableElements().slice(0, Math.max(1, maxElements || 500));
    const focused = document.activeElement && document.activeElement !== document.body
      ? serializeElement(document.activeElement, -1)
      : null;
    return {
      viewport: {
        width: window.innerWidth,
        height: window.innerHeight,
        scrollX: window.scrollX,
        scrollY: window.scrollY,
        deviceScaleFactor: window.devicePixelRatio || 1
      },
      focusedElement: focused ? {
        nodeID: focused.nodeID,
        tagName: focused.tagName,
        role: focused.role,
        text: focused.text,
        valuePreview: focused.valuePreview,
        isEditable: focused.isEditable
      } : null,
      interactables: elements.map((element, index) => serializeElement(element, index)),
      rawText: includeRawText ? (document.body ? String(document.body.innerText || document.body.textContent || "").slice(0, 20000) : "") : null,
      nodeCount: document.querySelectorAll("*").length
    };
  }

  function resolve(target) {
    if (!target) {
      return { ok: false, error: "missing_target", message: "No DOM target was supplied." };
    }
    const kind = target.kind;
    const value = target.value;
    if (kind === "browser_node_id") {
      const element = ids.get(String(value));
      if (element && isVisible(element)) {
        return { ok: true, element: serializeElement(element, -1) };
      }
      return { ok: false, error: "target_not_found", message: "No live element matched browser_node_id " + value + "." };
    }
    if (kind === "display_index") {
      const index = Number(value);
      const elements = interactableElements();
      const element = elements[index];
      if (element) {
        return { ok: true, element: serializeElement(element, index) };
      }
      return { ok: false, error: "target_not_found", message: "No interactable matched display_index " + value + "." };
    }
    if (kind === "dom_selector") {
      let matches;
      try {
        matches = Array.from(document.querySelectorAll(String(value))).filter(isVisible);
      } catch (error) {
        return { ok: false, error: "invalid_selector", message: String(error && error.message || error) };
      }
      if (matches.length === 1) {
        return { ok: true, element: serializeElement(matches[0], -1) };
      }
      if (matches.length > 1) {
        return {
          ok: false,
          error: "ambiguous_target",
          message: "Selector matched " + matches.length + " visible elements.",
          candidates: matches.slice(0, 10).map((element, index) => serializeElement(element, index))
        };
      }
      return { ok: false, error: "target_not_found", message: "No visible element matched selector " + value + "." };
    }
    return { ok: false, error: "unsupported_target_kind", message: "Unsupported target kind " + kind + "." };
  }

  function dispatchMouse(element, type, detail, point) {
    const event = new MouseEvent(type, {
      bubbles: true,
      cancelable: true,
      view: window,
      detail: detail || 1,
      clientX: point.x,
      clientY: point.y,
      button: 0
    });
    element.dispatchEvent(event);
  }

  function click(target, clickCount) {
    const resolved = resolve(target);
    if (!resolved.ok) return resolved;
    const element = resolved.element;
    const live = ids.get(element.nodeID);
    const point = element.centerViewport;
    const count = Math.max(1, Math.min(Number(clickCount || 1), 2));
    for (let index = 0; index < count; index++) {
      dispatchMouse(live, "pointerdown", count, point);
      dispatchMouse(live, "mousedown", count, point);
      dispatchMouse(live, "pointerup", count, point);
      dispatchMouse(live, "mouseup", count, point);
      dispatchMouse(live, "click", count, point);
    }
    if (count > 1) {
      dispatchMouse(live, "dblclick", count, point);
    }
    if (typeof live.click === "function") {
      live.click();
    }
    return { ok: true, element, valuePreview: valuePreview(live) };
  }

  function clickPoint(x, y, clickCount) {
    const point = { x: Number(x), y: Number(y) };
    const live = document.elementFromPoint(point.x, point.y);
    if (!live) return { ok: false, error: "target_not_found", message: "No element exists at the supplied viewport point." };
    const element = serializeElement(live, -1);
    const count = Math.max(1, Math.min(Number(clickCount || 1), 2));
    for (let index = 0; index < count; index++) {
      dispatchMouse(live, "pointerdown", count, point);
      dispatchMouse(live, "mousedown", count, point);
      dispatchMouse(live, "pointerup", count, point);
      dispatchMouse(live, "mouseup", count, point);
      dispatchMouse(live, "click", count, point);
    }
    if (count > 1) {
      dispatchMouse(live, "dblclick", count, point);
    }
    if (typeof live.click === "function") {
      live.click();
    }
    return { ok: true, element, valuePreview: valuePreview(live) };
  }

  function typeText(target, text, append) {
    const resolved = target ? resolve(target) : { ok: true, element: document.activeElement ? serializeElement(document.activeElement, -1) : null };
    if (!resolved.ok) return resolved;
    const live = resolved.element ? ids.get(resolved.element.nodeID) : document.activeElement;
    if (!live) return { ok: false, error: "target_not_found", message: "No editable element was focused or resolved." };
    live.focus();
    const value = String(text || "");
    if (live.isContentEditable) {
      if (!append) live.textContent = "";
      live.textContent = (live.textContent || "") + value;
      live.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: value }));
    } else if ("value" in live) {
      live.value = append ? String(live.value || "") + value : value;
      live.dispatchEvent(new InputEvent("input", { bubbles: true, inputType: "insertText", data: value }));
      live.dispatchEvent(new Event("change", { bubbles: true }));
    } else {
      return { ok: false, error: "not_editable", message: "Resolved element is not editable." };
    }
    return { ok: true, element: serializeElement(live, -1), valuePreview: valuePreview(live) };
  }

  function scroll(target, direction, pages) {
    let element = null;
    if (target) {
      const resolved = resolve(target);
      if (!resolved.ok) return resolved;
      element = ids.get(resolved.element.nodeID);
    }
    const amount = Math.max(1, Number(pages || 1)) * Math.max(240, Math.round(window.innerHeight * 0.8));
    const dx = direction === "left" ? -amount : direction === "right" ? amount : 0;
    const dy = direction === "up" ? -amount : direction === "down" ? amount : 0;
    const documentScroller = document.scrollingElement || document.documentElement;
    const canElementScroll = element &&
      element !== document.body &&
      element !== document.documentElement &&
      (element.scrollHeight > element.clientHeight || element.scrollWidth > element.clientWidth);
    const scroller = canElementScroll ? element : documentScroller;
    const useWindowScroll = !canElementScroll;
    const before = useWindowScroll
      ? { x: window.scrollX, y: window.scrollY }
      : { x: scroller.scrollLeft, y: scroller.scrollTop };
    if (useWindowScroll) {
      window.scrollBy({ left: dx, top: dy, behavior: "auto" });
    } else {
      scroller.scrollBy({ left: dx, top: dy, behavior: "auto" });
    }
    const after = useWindowScroll
      ? { x: window.scrollX, y: window.scrollY }
      : { x: scroller.scrollLeft, y: scroller.scrollTop };
    return { ok: true, before, after, delta: { x: after.x - before.x, y: after.y - before.y } };
  }

  function serialize(value, depth) {
    const level = depth || 0;
    if (value === undefined || value === null) return null;
    if (typeof value === "number" || typeof value === "string" || typeof value === "boolean") return value;
    if (value instanceof Element) return serializeElement(value, -1);
    if (Array.isArray(value)) return value.slice(0, 200).map(item => serialize(item, level + 1));
    if (typeof value === "object") {
      if (level > 4) return String(value);
      const out = {};
      for (const key of Object.keys(value).slice(0, 200)) {
        out[key] = serialize(value[key], level + 1);
      }
      return out;
    }
    return String(value);
  }

  function emit(type, payload, meta) {
    const message = {
      kind: "event",
      type: String(type || "event"),
      scriptID: meta && meta.scriptID ? String(meta.scriptID) : null,
      payload: serialize(payload)
    };
    if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.bcu) {
      window.webkit.messageHandlers.bcu.postMessage(message);
    }
    return message;
  }

  function consoleArgument(value) {
    try {
      return serialize(value);
    } catch (error) {
      try {
        return String(value);
      } catch (stringError) {
        return "[unserializable]";
      }
    }
  }

  function installConsoleBridge() {
    if (window.__bcuConsoleBridgeInstalled) return;
    window.__bcuConsoleBridgeInstalled = true;

    ["debug", "log", "info", "warn", "error"].forEach((level) => {
      const original = console[level];
      console[level] = function(...args) {
        try {
          emit("browser_console", {
            level,
            args: args.map(consoleArgument)
          }, { scriptID: "console" });
        } catch (bridgeError) {
        }
        if (typeof original === "function") {
          return original.apply(this, args);
        }
      };
    });

    window.addEventListener("error", (event) => {
      emit("browser_page_error", {
        message: event.message || String(event.error || "Error"),
        source: event.filename || null,
        line: event.lineno || null,
        column: event.colno || null,
        error: event.error ? String(event.error.stack || event.error) : null
      }, { scriptID: "page-error" });
    });

    window.addEventListener("unhandledrejection", (event) => {
      const reason = event.reason;
      emit("browser_unhandled_rejection", {
        message: reason ? String(reason.message || reason) : "Unhandled promise rejection",
        error: reason ? String(reason.stack || reason) : null
      }, { scriptID: "page-error" });
    });
  }

  installConsoleBridge();

  window.__bcu = {
    version: 1,
    snapshot,
    resolve,
    click,
    clickPoint,
    typeText,
    scroll,
    serialize,
    emit,
    receiveMessage(message) {
      window.dispatchEvent(new CustomEvent("bcu:message", { detail: message }));
    }
  };
})();
"""
}
