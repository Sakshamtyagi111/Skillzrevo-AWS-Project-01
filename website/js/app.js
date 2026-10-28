(function () {
  var meta = document.querySelector('meta[name="build"]');
  document.getElementById("build").textContent = meta ? meta.content : "dev";

  var files = ["/index.html", "/css/style.css", "/js/app.js", "/images/hero.svg"];
  var tbody = document.querySelector("#result tbody");

  async function probe(path) {
    var t0 = performance.now();
    var res = await fetch(path, { cache: "no-store" }); // bypass browser cache, hit the edge
    await res.arrayBuffer();
    var ms = Math.round(performance.now() - t0);
    var h = function (n) { return res.headers.get(n) || "–"; };
    return { path: path, ms: ms, xcache: h("x-cache"), age: h("age"), pop: h("x-amz-cf-pop"),
             cc: h("cache-control"), ver: h("x-amz-version-id") };
  }

  async function run() {
    tbody.innerHTML = "";
    for (var i = 0; i < files.length; i++) {
      var tr = document.createElement("tr");
      try {
        var r = await probe(files[i]);
        var cls = /hit/i.test(r.xcache) ? "hit" : "miss";
        [r.path, r.ms + " ms", r.xcache, r.age, r.pop, r.cc, r.ver].forEach(function (v, idx) {
          var td = document.createElement("td");
          td.textContent = v;
          if (idx === 2) td.className = cls;
          tr.appendChild(td);
        });
      } catch (e) {
        var td = document.createElement("td");
        td.colSpan = 7;
        td.textContent = "Failed: " + files[i];
        tr.appendChild(td);
      }
      tbody.appendChild(tr);
    }
  }
  document.getElementById("run").addEventListener("click", run);
})();
