(() => {
  const downloadLinks = document.querySelectorAll("[data-download]");
  if (downloadLinks.length === 0) return;

  fetch("release.json", { cache: "no-store" })
    .then((response) => {
      if (!response.ok) throw new Error(`release metadata: ${response.status}`);
      return response.json();
    })
    .then((release) => {
      if (!release.available || !release.downloadUrl) return;

      downloadLinks.forEach((link) => {
        link.href = release.downloadUrl;
        const label = link.querySelector("[data-download-label]");
        const meta = link.querySelector("[data-download-meta]");
        if (label) label.textContent = `Download ${release.tag}`;
        if (meta) meta.textContent = "Signed and notarized DMG";
      });
    })
    .catch(() => {
      // The static releases link remains fully functional without metadata.
    });
})();
