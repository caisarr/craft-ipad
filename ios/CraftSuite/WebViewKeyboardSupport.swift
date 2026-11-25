import ObjectiveC.runtime
import UIKit
import WebKit

/// Touch, scroll, and keyboard fixes for egui/eframe canvases running inside WKWebView on iPadOS.
///
/// 1. Lifts WebKit's user-gesture requirement for programmatic `.focus()` so egui's hidden `<input>`
///    can raise the on-screen keyboard when a cell or document area is tapped.
/// 2. Debounces blur/canvas-focus ping-pong between frames so the virtual keyboard stays steady.
/// 3. Deduplicates iPadOS `touch*` + `pointer*` events (preventing single taps from registering as
///    double-clicks), converts 1-finger drags in Scroll mode (and 2-finger drags in any mode) into
///    smooth `wheel` events with momentum, and supports a live Scroll/Select mode toggle.
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

    static let touchAndKeyboardBridgeJS = """
    (function() {
      if (window.__craftBridgeInstalled) return;
      window.__craftBridgeInstalled = true;

      // 1. Disable iOS native callout/selection loupe over the WebGL/WebGPU canvas.
      function injectStyle() {
        var parent = document.head || document.documentElement;
        if (!parent || document.getElementById('__craft_touch_style')) return;
        var style = document.createElement('style');
        style.id = '__craft_touch_style';
        style.textContent = 'html, body, canvas { -webkit-user-select: none !important; user-select: none !important; -webkit-touch-callout: none !important; touch-action: none !important; overscroll-behavior: none !important; }';
        parent.appendChild(style);
      }

      function findCanvas() {
        return document.querySelector('canvas');
      }

      function ensureFocusable() {
        injectStyle();
        var canvas = findCanvas();
        if (canvas && !canvas.hasAttribute('tabindex')) {
          canvas.setAttribute('tabindex', '0');
        }
        return canvas;
      }

      function isEguiHiddenInput(el) {
        return !!(el && el.tagName === 'INPUT' && el.style && el.style.opacity === '0' && el.style.pointerEvents === 'none');
      }

      function findEguiHiddenInput() {
        var inputs = document.querySelectorAll('input');
        for (var i = 0; i < inputs.length; i++) {
          if (isEguiHiddenInput(inputs[i])) return inputs[i];
        }
        return null;
      }

      function nothingFocused() {
        var el = document.activeElement;
        return !el || el === document.body || el === document.documentElement;
      }

      // 2. Focus-debounce shield (150ms) to stop virtual keyboard bounce.
      var origInputBlur = HTMLInputElement.prototype.blur;
      var origHtmlFocus = HTMLElement.prototype.focus;
      var pendingBlurTimer = null;
      var pendingCanvasFocusTimer = null;
      var allowImmediateBlur = false;

      function clearFocusTimers() {
        if (pendingBlurTimer !== null) {
          clearTimeout(pendingBlurTimer);
          pendingBlurTimer = null;
        }
        if (pendingCanvasFocusTimer !== null) {
          clearTimeout(pendingCanvasFocusTimer);
          pendingCanvasFocusTimer = null;
        }
      }

      HTMLInputElement.prototype.blur = function() {
        var self = this;
        if (isEguiHiddenInput(self) && !allowImmediateBlur) {
          if (pendingBlurTimer !== null) clearTimeout(pendingBlurTimer);
          pendingBlurTimer = setTimeout(function() {
            pendingBlurTimer = null;
            if (document.activeElement === self) {
              origInputBlur.call(self);
            }
          }, 150);
          return;
        }
        return origInputBlur.apply(self, arguments);
      };

      HTMLElement.prototype.focus = function() {
        var self = this;
        var args = arguments;
        if (isEguiHiddenInput(self)) {
          clearFocusTimers();
          if (document.activeElement === self) {
            return;
          }
          return origHtmlFocus.apply(self, args);
        }
        if (self.tagName === 'CANVAS' && isEguiHiddenInput(document.activeElement)) {
          if (pendingCanvasFocusTimer !== null) clearTimeout(pendingCanvasFocusTimer);
          pendingCanvasFocusTimer = setTimeout(function() {
            pendingCanvasFocusTimer = null;
            if (!isEguiHiddenInput(document.activeElement)) {
              origHtmlFocus.apply(self, args);
            }
          }, 150);
          return;
        }
        return origHtmlFocus.apply(self, args);
      };

      window.__craftTouchMode = window.__craftTouchMode || 'scroll';
      window.__craftSetTouchMode = function(mode) {
        window.__craftTouchMode = (mode === 'select' ? 'select' : 'scroll');
      };

      window.__craftToggleKeyboard = function() {
        clearFocusTimers();
        var active = document.activeElement;
        if (isEguiHiddenInput(active)) {
          allowImmediateBlur = true;
          try { origInputBlur.call(active); } finally { allowImmediateBlur = false; }
          var canvas = ensureFocusable();
          if (canvas) {
            try { origHtmlFocus.call(canvas, { preventScroll: true }); } catch (e) {}
          }
          return 'hidden';
        }
        var hiddenInput = findEguiHiddenInput();
        if (hiddenInput) {
          try { origHtmlFocus.call(hiddenInput, { preventScroll: true }); } catch (e) {}
          return 'shown';
        }
        var c = ensureFocusable();
        if (c) {
          try { origHtmlFocus.call(c, { preventScroll: true }); } catch (e) {}
        }
        return 'none';
      };

      // 3. Deduplicated Touch & Smooth Scroll Controller.
      // Block raw touch/pen PointerEvents so eframe never sees duplicate pointer + touch clicks,
      // while leaving hardware mouse/trackpad (`pointerType === 'mouse'`) completely untouched.
      ['pointerdown', 'pointerup', 'pointermove', 'pointercancel'].forEach(function(type) {
        window.addEventListener(type, function(ev) {
          if (!ev.__craftSynth && (ev.pointerType === 'touch' || ev.pointerType === 'pen')) {
            ev.stopImmediatePropagation();
          }
        }, true);
      });

      var gestureActive = false;
      var state = 'idle'; // 'idle' | 'pending' | 'scrolling' | 'selecting' | 'twofinger'
      var startX = 0, startY = 0;
      var lastX = 0, lastY = 0, lastTime = 0;
      var vx = 0, vy = 0;
      var momentumRaf = null;
      var twoFinger = null;

      function stopMomentum() {
        if (momentumRaf !== null) {
          cancelAnimationFrame(momentumRaf);
          momentumRaf = null;
        }
      }

      function dispatchPointer(target, type, x, y, buttons) {
        var ev = new PointerEvent(type, {
          pointerId: 1,
          pointerType: 'mouse',
          isPrimary: true,
          button: 0,
          buttons: buttons,
          clientX: x,
          clientY: y,
          bubbles: true,
          cancelable: true,
          composed: true,
          view: window
        });
        ev.__craftSynth = true;
        target.dispatchEvent(ev);
      }

      function dispatchMouseMove(target, x, y, buttons) {
        var ev = new MouseEvent('mousemove', {
          clientX: x,
          clientY: y,
          buttons: buttons,
          bubbles: true,
          cancelable: true,
          view: window
        });
        target.dispatchEvent(ev);
      }

      function dispatchWheel(target, dx, dy, x, y, isZoom) {
        var ev = new WheelEvent('wheel', {
          deltaX: dx,
          deltaY: dy,
          deltaMode: 0,
          ctrlKey: !!isZoom,
          clientX: x,
          clientY: y,
          bubbles: true,
          cancelable: true
        });
        target.dispatchEvent(ev);
      }

      function twoFingerMetrics(touches) {
        var t0 = touches[0], t1 = touches[1];
        var midX = (t0.clientX + t1.clientX) * 0.5;
        var midY = (t0.clientY + t1.clientY) * 0.5;
        var dist = Math.hypot(t1.clientX - t0.clientX, t1.clientY - t0.clientY);
        return { midX: midX, midY: midY, dist: dist };
      }

      function startMomentum(canvas, x, y) {
        stopMomentum();
        var frames = 0;
        var curVx = Math.max(-60, Math.min(60, vx));
        var curVy = Math.max(-60, Math.min(60, vy));
        function step() {
          if (frames >= 28 || Math.hypot(curVx, curVy) < 0.6) {
            momentumRaf = null;
            return;
          }
          frames++;
          dispatchWheel(canvas, -curVx, -curVy, x, y, false);
          curVx *= 0.90;
          curVy *= 0.90;
          momentumRaf = requestAnimationFrame(step);
        }
        if (Math.hypot(curVx, curVy) > 1.2) {
          momentumRaf = requestAnimationFrame(step);
        }
      }

      document.addEventListener('touchstart', function(ev) {
        var canvas = ensureFocusable();
        if (!canvas) return;
        if (!gestureActive && ev.target !== canvas) return;

        stopMomentum();
        gestureActive = true;

        if (ev.touches.length >= 2) {
          if (state === 'selecting') {
            dispatchPointer(canvas, 'pointerup', lastX, lastY, 0);
          }
          state = 'twofinger';
          twoFinger = twoFingerMetrics(ev.touches);
          ev.preventDefault();
          ev.stopImmediatePropagation();
          return;
        }

        var t = ev.touches[0];
        startX = lastX = t.clientX;
        startY = lastY = t.clientY;
        lastTime = performance.now();
        vx = 0;
        vy = 0;

        if (window.__craftTouchMode === 'select') {
          state = 'selecting';
          dispatchMouseMove(canvas, startX, startY, 0);
          dispatchPointer(canvas, 'pointerdown', startX, startY, 1);
        } else {
          state = 'pending';
        }

        ev.preventDefault();
        ev.stopImmediatePropagation();
      }, { capture: true, passive: false });

      document.addEventListener('touchmove', function(ev) {
        if (!gestureActive) return;
        var canvas = findCanvas();
        if (!canvas) return;

        if (ev.touches.length >= 2) {
          var m = twoFingerMetrics(ev.touches);
          if (twoFinger) {
            var dx = m.midX - twoFinger.midX;
            var dy = m.midY - twoFinger.midY;
            var dDist = m.dist - twoFinger.dist;
            if (Math.abs(dx) > 0.1 || Math.abs(dy) > 0.1) {
              dispatchWheel(canvas, -dx * 1.35, -dy * 1.35, m.midX, m.midY, false);
            }
            if (Math.abs(dDist) > 1.5) {
              dispatchWheel(canvas, 0, -dDist * 2.2, m.midX, m.midY, true);
            }
          }
          twoFinger = m;
          state = 'twofinger';
          ev.preventDefault();
          ev.stopImmediatePropagation();
          return;
        }

        if (state === 'twofinger') {
          ev.preventDefault();
          ev.stopImmediatePropagation();
          return;
        }

        var t = ev.touches[0];
        var x = t.clientX;
        var y = t.clientY;

        if (state === 'selecting') {
          lastX = x;
          lastY = y;
          dispatchMouseMove(canvas, x, y, 1);
          ev.preventDefault();
          ev.stopImmediatePropagation();
          return;
        }

        if (state === 'pending' && Math.hypot(x - startX, y - startY) >= 10) {
          state = 'scrolling';
          lastX = x;
          lastY = y;
          lastTime = performance.now();
          ev.preventDefault();
          ev.stopImmediatePropagation();
          return;
        }

        if (state === 'scrolling') {
          var now = performance.now();
          var dt = Math.max(8, now - lastTime);
          var dx1 = x - lastX;
          var dy1 = y - lastY;
          dispatchWheel(canvas, -dx1 * 1.35, -dy1 * 1.35, x, y, false);
          var instVx = (dx1 * 1.35) / (dt / 16.0);
          var instVy = (dy1 * 1.35) / (dt / 16.0);
          vx = vx * 0.4 + instVx * 0.6;
          vy = vy * 0.4 + instVy * 0.6;
          lastX = x;
          lastY = y;
          lastTime = now;
        }

        ev.preventDefault();
        ev.stopImmediatePropagation();
      }, { capture: true, passive: false });

      function finishTouch(ev, cancelled) {
        if (!gestureActive) return;
        var canvas = findCanvas();

        if (ev.touches.length > 0) {
          if (state === 'twofinger') {
            if (ev.touches.length >= 2) {
              twoFinger = twoFingerMetrics(ev.touches);
            } else {
              twoFinger = null;
            }
          }
          ev.preventDefault();
          ev.stopImmediatePropagation();
          return;
        }

        var t = ev.changedTouches && ev.changedTouches[0];
        var x = t ? t.clientX : lastX;
        var y = t ? t.clientY : lastY;

        if (canvas && !cancelled) {
          if (state === 'pending') {
            dispatchMouseMove(canvas, x, y, 0);
            dispatchPointer(canvas, 'pointerdown', x, y, 1);
            dispatchPointer(canvas, 'pointerup', x, y, 0);
            if (nothingFocused()) {
              try { origHtmlFocus.call(canvas, { preventScroll: true }); } catch (e) {}
            }
          } else if (state === 'scrolling') {
            startMomentum(canvas, x, y);
          } else if (state === 'selecting') {
            dispatchPointer(canvas, 'pointerup', x, y, 0);
          }
        } else if (canvas && state === 'selecting') {
          dispatchPointer(canvas, 'pointerup', x, y, 0);
        }

        gestureActive = false;
        state = 'idle';
        twoFinger = null;
        ev.preventDefault();
        ev.stopImmediatePropagation();
      }

      document.addEventListener('touchend', function(ev) { finishTouch(ev, false); }, { capture: true, passive: false });
      document.addEventListener('touchcancel', function(ev) { finishTouch(ev, true); }, { capture: true, passive: false });

      // 4. External hardware keyboard fallback when nothing in the DOM is focused.
      ['keydown', 'keyup'].forEach(function(type) {
        window.addEventListener(type, function(ev) {
          if (ev.__craftRedispatched) return;
          if (!nothingFocused()) return;
          var canvas = ensureFocusable();
          if (!canvas) return;

          try { origHtmlFocus.call(canvas, { preventScroll: true }); } catch (e) {}
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
