import ObjectiveC.runtime
import UIKit
import WebKit

/// Keyboard fixes for egui/eframe canvases running inside WKWebView on iPadOS.
///
/// egui receives text through a hidden `<input>` that it focuses from its own frame logic, not
/// directly inside the user's tap handler. WebKit on iOS only shows the on-screen keyboard for a
/// focus it considers "user interacting", so the keyboard never appears. Sideloaded builds can
/// lift that restriction the same way Cordova/Capacitor's `KeyboardDisplayRequiresUserAction`
/// option does: treat every element focus as user-initiated.
enum WebViewKeyboardSupport {
    private static var didInstall = false

    static func install() {
        guard !didInstall else { return }
        didInstall = true
        allowProgrammaticFocusToShowKeyboard()
    }

    private static func allowProgrammaticFocusToShowKeyboard() {
        guard let contentViewClass = NSClassFromString("WKContentView") else { return }

        // iOS 13+ uses `activityStateChanges:`, iOS 12.2 used `changingActivityState:`.
        let selectorNames = [
            "_elementDidFocus:userIsInteracting:blurPreviousNode:activityStateChanges:userObject:",
            "_elementDidFocus:userIsInteracting:blurPreviousNode:changingActivityState:userObject:",
        ]

        typealias OriginalFn = @convention(c) (
            AnyObject, Selector, UnsafeRawPointer?, Bool, Bool, UInt64, AnyObject?
        ) -> Void

        for name in selectorNames {
            let selector = NSSelectorFromString(name)
            guard let method = class_getInstanceMethod(contentViewClass, selector) else { continue }

            let originalIMP = method_getImplementation(method)
            let original = unsafeBitCast(originalIMP, to: OriginalFn.self)

            let override: @convention(block) (
                AnyObject, UnsafeRawPointer?, Bool, Bool, UInt64, AnyObject?
            ) -> Void = { contentView, focusedElement, _, blurPreviousNode, activityState, userObject in
                original(contentView, selector, focusedElement, true, blurPreviousNode, activityState, userObject)
            }

            method_setImplementation(method, imp_implementationWithBlock(override))
            return
        }
    }

    /// Makes hardware keyboard input reach egui's canvas.
    ///
    /// eframe listens for `keydown`/`keyup` on the `<canvas>` only. If nothing in the page is
    /// focused (activeElement is `<body>`), keys go nowhere, so this script gives the canvas a
    /// tabindex, focuses it on touch, and re-dispatches stray key events to it.
    static let canvasFocusBridgeJS = """
    (function() {
      if (window.__craftKeyboardHooked) return;
      window.__craftKeyboardHooked = true;

      function findCanvas() {
        return document.querySelector('canvas');
      }

      function ensureFocusable() {
        var canvas = findCanvas();
        if (canvas && !canvas.hasAttribute('tabindex')) {
          canvas.setAttribute('tabindex', '0');
        }
        return canvas;
      }

      function nothingFocused() {
        var el = document.activeElement;
        return !el || el === document.body || el === document.documentElement;
      }

      function focusCanvas(canvas) {
        try { canvas.focus({ preventScroll: true }); } catch (e) {}
      }

      function onPointer() {
        var canvas = ensureFocusable();
        if (canvas && nothingFocused()) {
          focusCanvas(canvas);
        }
      }

      document.addEventListener('pointerdown', onPointer, true);
      document.addEventListener('touchstart', onPointer, { capture: true, passive: true });

      ['keydown', 'keyup'].forEach(function(type) {
        window.addEventListener(type, function(ev) {
          if (ev.__craftRedispatched) return;
          if (!nothingFocused()) return;
          var canvas = ensureFocusable();
          if (!canvas) return;

          focusCanvas(canvas);
          var clone = new KeyboardEvent(type, {
            key: ev.key,
            code: ev.code,
            location: ev.location,
            repeat: ev.repeat,
            ctrlKey: ev.ctrlKey,
            shiftKey: ev.shiftKey,
            altKey: ev.altKey,
            metaKey: ev.metaKey,
            bubbles: true,
            cancelable: true,
            composed: true
          });
          clone.__craftRedispatched = true;
          ev.preventDefault();
          ev.stopPropagation();
          canvas.dispatchEvent(clone);
        }, true);
      });

      if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', ensureFocusable);
      } else {
        ensureFocusable();
      }
      new MutationObserver(ensureFocusable).observe(document.documentElement, { childList: true, subtree: true });
    })();
    """
}
