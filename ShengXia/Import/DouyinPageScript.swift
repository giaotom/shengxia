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
      function scan() {
        try {
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
          post({ kind: "page", href: String(location.href), title: document.title || "" });
        } catch (e) {}
      }
      setInterval(scan, 800);
      post({ kind: "page", href: String(location.href), title: "" });
    })();
    """
}
