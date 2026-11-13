import Foundation

enum DouyinPageScript {
    static let source = """
    (function () {
      if (window.__shengxiaInstalled) return;
      window.__shengxiaInstalled = true;
      function post(obj) {
        try { window.webkit.messageHandlers.shengxia.postMessage(obj); } catch (e) {}
      }
      function interesting(url) {
        if (!url) return false;
        var u = String(url).toLowerCase();
        if (u.indexOf("blob:") === 0 || u.indexOf("data:") === 0) return false;
        var keys = ["zjcdn.com", "douyinvod.com", "douyincdn.com", "bytevod.com", "ixigua.com", "aweme/v1/play", "media-audio", "media-video", ".mp4"];
        for (var i = 0; i < keys.length; i++) if (u.indexOf(keys[i]) !== -1) return true;
        return false;
      }
      var origFetch = window.fetch;
      if (typeof origFetch === "function") {
        window.fetch = function () {
          var args = arguments;
          var input = args[0];
          var url = typeof input === "string" ? input : (input && input.url) || "";
          return origFetch.apply(this, args).then(function (res) {
            try {
              var finalURL = String(res.url || url || "");
              if (finalURL.indexOf("aweme/detail") !== -1 || finalURL.indexOf("iteminfo") !== -1) {
                res.clone().text().then(function (text) {
                  post({ kind: "detail", url: finalURL, href: String(location.href), body: String(text).slice(0, 1500000) });
                }).catch(function () {});
              } else if (interesting(finalURL)) {
                post({ kind: "media", url: finalURL, href: String(location.href) });
              }
            } catch (e) {}
            return res;
          });
        };
      }
      var origOpen = XMLHttpRequest.prototype.open;
      var origSend = XMLHttpRequest.prototype.send;
      XMLHttpRequest.prototype.open = function (method, url) {
        this.__sxURL = url;
        return origOpen.apply(this, arguments);
      };
      XMLHttpRequest.prototype.send = function () {
        var xhr = this;
        xhr.addEventListener("load", function () {
          try {
            var url = String(xhr.responseURL || xhr.__sxURL || "");
            if (url.indexOf("aweme/detail") !== -1 || url.indexOf("iteminfo") !== -1) {
              var text = typeof xhr.responseText === "string" ? xhr.responseText : "";
              post({ kind: "detail", url: url, href: String(location.href), body: text.slice(0, 1500000) });
            } else if (interesting(url)) {
              post({ kind: "media", url: url, href: String(location.href) });
            }
          } catch (e) {}
        });
        return origSend.apply(this, arguments);
      };
      var origPlay = HTMLMediaElement.prototype.play;
      HTMLMediaElement.prototype.play = function () {
        try { this.muted = true; } catch (e) {}
        return origPlay.apply(this, arguments);
      };
      function tuneViewport() {
        try {
          var content = "width=device-width, initial-scale=1, minimum-scale=0.5, maximum-scale=5, user-scalable=yes";
          var metas = document.getElementsByTagName("meta");
          var found = false;
          for (var i = 0; i < metas.length; i++) {
            if (String(metas[i].name || "").toLowerCase() === "viewport") {
              metas[i].setAttribute("content", content);
              found = true;
            }
          }
          if (!found && document.head) {
            var meta = document.createElement("meta");
            meta.name = "viewport";
            meta.content = content;
            document.head.appendChild(meta);
          }
        } catch (e) {}
      }
      function considerCaptcha(el, best) {
        if (!el || !el.getBoundingClientRect) return best;
        var rect = el.getBoundingClientRect();
        var area = rect.width * rect.height;
        if (rect.width < 80 || rect.height < 48 || area <= best.area) return best;
        return { el: el, area: area };
      }
      function findCaptcha() {
        var selectors = [
          "#captcha_container",
          ".captcha_verify_container",
          ".captcha-verify-container",
          "#captcha-verify-image",
          ".secsdk-captcha",
          ".secsdk_captcha_wrapper",
          "[class*='captcha_verify']",
          "[class*='captcha-verify']",
          "iframe[src*='captcha']",
          "iframe[src*='verify']"
        ];
        var best = { el: null, area: 0 };
        for (var i = 0; i < selectors.length; i++) {
          var nodes;
          try { nodes = document.querySelectorAll(selectors[i]); } catch (e) { continue; }
          for (var j = 0; j < nodes.length; j++) best = considerCaptcha(nodes[j], best);
        }
        if (best.el) return best.el;
        var text = "";
        try { text = document.body ? (document.body.innerText || "") : ""; } catch (e) {}
        if (text.indexOf("拖动滑块") !== -1 || text.indexOf("滑动验证") !== -1 || text.indexOf("向右拖动") !== -1 || text.indexOf("请完成下列验证") !== -1) {
          return document.body || null;
        }
        return null;
      }
      function revealCaptcha() {
        tuneViewport();
        var el = findCaptcha();
        if (!el) return false;
        try { document.documentElement.style.zoom = "1.5"; } catch (e) {}
        try {
          el.scrollIntoView({ block: "center", inline: "center" });
        } catch (e) {
          try { el.scrollIntoView(true); } catch (e2) {}
        }
        return true;
      }
      window.__shengxiaRevealCaptcha = revealCaptcha;
      var verifyOn = false;
      function watchVerification() {
        var el = findCaptcha();
        if (el && !verifyOn) {
          verifyOn = true;
          revealCaptcha();
          post({ kind: "verify", active: true, href: String(location.href) });
        } else if (!el && verifyOn) {
          verifyOn = false;
          try { document.documentElement.style.zoom = ""; } catch (e) {}
          post({ kind: "verify", active: false, href: String(location.href) });
        }
      }
      function scan() {
        try {
          tuneViewport();
          var entries = performance.getEntriesByType("resource");
          for (var i = 0; i < entries.length; i++) {
            if (interesting(entries[i].name)) post({ kind: "media", url: String(entries[i].name), href: String(location.href) });
          }
          var videos = document.querySelectorAll("video");
          for (var j = 0; j < videos.length; j++) {
            videos[j].muted = true;
            var src = videos[j].currentSrc || videos[j].src || "";
            if (interesting(src)) post({ kind: "media", url: String(src), href: String(location.href) });
          }
          watchVerification();
          post({ kind: "page", href: String(location.href), title: document.title || "" });
        } catch (e) {}
      }
      setInterval(scan, 800);
      tuneViewport();
      post({ kind: "page", href: String(location.href), title: "" });
    })();
    """

    static let revealInvocation = "window.__shengxiaRevealCaptcha && window.__shengxiaRevealCaptcha()"
}
