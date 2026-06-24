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
        "Version non vérifiée",
        "Impossible de joindre GitHub Releases pour le moment.",
        "Le script reste disponible directement depuis le dépôt."
      );
      return;
    }

    if (!response.ok) {
      setFallback(
        "Version non vérifiée",
        "GitHub Releases n'a pas répondu correctement.",
        "Consultez le dépôt GitHub si vous voulez vérifier manuellement les fichiers disponibles."
      );
      return;
    }

    const releases = await response.json();
    const release = Array.isArray(releases)
      ? releases.find((item) => !item.draft && !item.prerelease)
      : null;

    if (!release) {
      setFallback(
        "Aucune version publiée",
        "La première mise en ligne officielle n'est pas encore publiée.",
        "Le bouton principal télécharge le script depuis la branche main."
      );
      return;
    }

    const assets = Array.isArray(release.assets) ? release.assets : [];
    const downloadAsset = findDownload(assets);
    const shaAsset = downloadAsset ? findSha(assets, downloadAsset.name) : null;
    const releaseDate = release.published_at ? new Date(release.published_at) : null;
    const releaseDateText = releaseDate
      ? releaseDate.toLocaleDateString("fr-CA", { year: "numeric", month: "long", day: "numeric" })
      : "date non publiée";

    setText(title, release.name || release.tag_name || "Version publiée");
    setText(summary, `Mise en ligne officielle publiée le ${releaseDateText}.`);

    if (details) {
      details.hidden = false;
    }

    if (downloadAsset) {
      setText(packageTarget, downloadAsset.name);
      if (primaryDownloadLink) {
        primaryDownloadLink.href = downloadAsset.browser_download_url;
      }
    } else {
      setText(packageTarget, "Aucun fichier téléchargeable joint à cette version.");
      if (primaryDownloadLink) {
        primaryDownloadLink.href = release.html_url || releasesUrl;
      }
    }

    const shaValue = shaFromAssetDigest(downloadAsset) || await shaFromFile(shaAsset);
    setText(shaTarget, shaValue || "Non publiée avec cette mise en ligne.");

    if (note) {
      note.hidden = true;
    }
  };

  hydrate();
})();
