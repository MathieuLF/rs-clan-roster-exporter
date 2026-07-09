(() => {
  const repo = "MathieuLF/rs-clan-roster-exporter";
  const releasesUrl = `https://github.com/${repo}/releases`;
  const rawScriptUrl = `https://raw.githubusercontent.com/${repo}/main/Get-RunescapeClanMembers.ps1`;
  const apiUrl = `https://api.github.com/repos/${repo}/releases?per_page=10`;
  const card = document.querySelector("[data-release-card]");

  if (!card) {
    return;
  }

  const title = document.querySelector("#release-title");
  const summary = card.querySelector("[data-release-summary]");
  const details = card.querySelector("[data-release-details]");
  const packageTarget = card.querySelector("[data-release-package]");
  const shaTarget = card.querySelector("[data-release-sha]");
  const note = card.querySelector("[data-release-note]");
  const primaryDownloadLink = document.querySelector("[data-primary-download]");

  const setText = (element, value) => {
    if (element) {
      element.textContent = value;
    }
  };

  const showNote = (message) => {
    if (note) {
      note.hidden = false;
      note.textContent = message;
    }
  };

  const setFallback = (heading, message, noteText) => {
    setText(title, heading);
    setText(summary, message);
    if (details) {
      details.hidden = true;
    }
    if (primaryDownloadLink) {
      primaryDownloadLink.href = rawScriptUrl;
    }
    showNote(noteText);
  };

  const findAsset = (assets, matcher) =>
    assets.find((asset) => matcher.test(asset.name || ""));

  const findDownload = (assets) =>
    findAsset(assets, /\.ps1$/i) || findAsset(assets, /\.zip$/i);

  const findSha = (assets, downloadName) => {
    if (downloadName) {
      const escaped = downloadName.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
      const direct = findAsset(assets, new RegExp(`${escaped}\\.sha256$`, "i"));
      if (direct) {
        return direct;
      }
    }

    return findAsset(assets, /\.sha256$/i);
  };

  const shaFromAssetDigest = (asset) => {
    const digest = asset && asset.digest ? String(asset.digest) : "";
    const match = digest.match(/sha256:([a-f0-9]{64})/i);
    return match ? match[1].toUpperCase() : "";
  };

  const shaFromFile = async (asset) => {
    if (!asset || !asset.browser_download_url) {
      return "";
    }

    try {
      const response = await fetch(asset.browser_download_url, { cache: "no-store" });
      if (!response.ok) {
        return "";
      }
      const text = await response.text();
      const match = text.match(/[a-f0-9]{64}/i);
      return match ? match[0].toUpperCase() : "";
    } catch (_error) {
      return "";
    }
  };

  const hydrate = async () => {
    let response;

    try {
      response = await fetch(apiUrl, {
        headers: { Accept: "application/vnd.github+json" },
        cache: "no-store",
      });
    } catch (_error) {
      setFallback(
        "Release not verified",
        "GitHub Releases cannot be reached right now.",
        "The script remains available directly from the repository."
      );
      return;
    }

    if (!response.ok) {
      setFallback(
        "Release not verified",
        "GitHub Releases did not respond successfully.",
        "Open the GitHub repository if you want to verify the available files manually."
      );
      return;
    }

    const releases = await response.json();
    const release = Array.isArray(releases)
      ? releases.find((item) => !item.draft && !item.prerelease)
      : null;

    if (!release) {
      setFallback(
        "No release published",
        "The first official release has not been published yet.",
        "The primary button downloads the script from the main branch."
      );
      return;
    }

    const assets = Array.isArray(release.assets) ? release.assets : [];
    const downloadAsset = findDownload(assets);
    const shaAsset = downloadAsset ? findSha(assets, downloadAsset.name) : null;
    const releaseDate = release.published_at ? new Date(release.published_at) : null;
    const releaseDateText = releaseDate
      ? releaseDate.toLocaleDateString("en-CA", { year: "numeric", month: "long", day: "numeric" })
      : "unpublished date";

    setText(title, release.name || release.tag_name || "Published release");
    setText(summary, `Official release published on ${releaseDateText}.`);

    if (details) {
      details.hidden = false;
    }

    if (downloadAsset) {
      setText(packageTarget, downloadAsset.name);
      if (primaryDownloadLink) {
        primaryDownloadLink.href = downloadAsset.browser_download_url;
      }
    } else {
      setText(packageTarget, "No downloadable file is attached to this release.");
      if (primaryDownloadLink) {
        primaryDownloadLink.href = release.html_url || releasesUrl;
      }
    }

    const shaValue = shaFromAssetDigest(downloadAsset) || await shaFromFile(shaAsset);
    setText(shaTarget, shaValue || "Not published with this release.");

    if (note) {
      note.hidden = true;
    }
  };

  hydrate();
})();
