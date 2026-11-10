const mangayomiSources = [
  {
    "name": "ReadComicsOnline Custom",
    "lang": "en",
    "baseUrl": "https://readcomicsonline.ru",
    "apiUrl": "",
    "iconUrl": "https://www.google.com/s2/favicons?sz=256&domain=https://readcomicsonline.ru/",
    "typeSource": "single",
    "itemType": 0,
    "version": "0.1.5",
    "pkgPath": "readcomicsonline.js"
  }
];

class DefaultExtension extends MProvider {
  constructor() {
    super();
    this.client = new Client();
  }

  getPreference(key) {
    return new SharedPreferences().get(key);
  }

  getHeaders() {
    return {
      "User-Agent":
        "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
      "Referer": "https://readcomicsonline.ru/",
      "Origin": "https://readcomicsonline.ru",
    };
  }

  async request(slug) {
    var url = slug;
    var baseUrl = this.source.baseUrl;
    if (!slug.includes(baseUrl)) url = baseUrl + slug;
    var res = await this.client.get(url, this.getHeaders());
    return new Document(res.body);
  }

  async getListPage(slug, page) {
    var url = `${slug}page=${page}`;
    var doc = await this.request(url);
    var baseUrl = this.source.baseUrl;
    var list = [];

    var comicList = doc.select(".list-comic > .item") || doc.select(".group-item") || [];
    
    if (comicList && comicList.length > 0) {
      comicList.forEach((item) => {
        var titleEl = item.selectFirst(".title") || item.selectFirst("a");
        var name = titleEl ? titleEl.text.trim() : "";
        
        var linkEl = item.selectFirst("a");
        var link = linkEl ? linkEl.getHref : "";

        var imgEl = item.selectFirst("img");
        var imageSlug = imgEl ? imgEl.getSrc : "";
        var imageUrl = imageSlug.includes("http")
          ? imageSlug
          : `${baseUrl}${imageSlug}`;

        if (name && link) {
          list.push({ name, link, imageUrl });
        }
      });
    }

    var pager = doc.select("ul.pager > li") || [];
    var hasNextPage = false;
    if (pager.length > 0) {
      hasNextPage = pager[pager.length - 1].text.includes("Last") || pager[pager.length - 1].text.includes("Next");
    }

    return { list, hasNextPage };
  }

  async getPopular(page) {
    return await this.getListPage("/ComicList/MostPopular?", page);
  }

  get supportsLatest() {
    return true;
  }

  async getLatestUpdates(page) {
    return await this.getListPage("/ComicList/LatestUpdate?", page);
  }

  async search(query, page, filters) {
    function getFilter(state) {
      var rd = "";
      if (!state) return rd;
      state.forEach((item) => {
        if (item.state) {
          rd += `${item.value},`;
        }
      });
      return rd.slice(0, -1);
    }

    var isFiltersAvailable = filters && filters.length > 0;
    var genre = isFiltersAvailable ? getFilter(filters[0].state) : "";
    var status = (isFiltersAvailable && filters[1]) ? filters[1].values[filters[1].state].value : "";
    var year = (isFiltersAvailable && filters[2]) ? filters[2].values[filters[2].state].value : "";

    var slug = `/AdvanceSearch?comicName=${encodeURIComponent(query)}&ig=${encodeURIComponent(
      genre
    )}&status=${status}&pubDate=${year}&`;

    return await this.getListPage(slug, page);
  }

  async getDetail(url) {
    function statusCode(status) {
      return (
        {
          "Ongoing": 0,
          "Completed": 1,
        }[status] ?? 5
      );
    }

    var baseUrl = this.source.baseUrl;
    if (url.includes(baseUrl)) url = url.replace(baseUrl, "");

    var doc = await this.request(url);

    var detailsSection = doc.selectFirst(".barContent");
    if (!detailsSection) {
      throw new Error("Impossibile caricare i dettagli (Cloudflare o struttura cambiata)");
    }

    var nameEl = detailsSection.selectFirst("a");
    var name = nameEl ? nameEl.text.trim() : "Unknown";

    var rightBox = doc.selectFirst(".rightBox");
    var imgEl = rightBox ? rightBox.selectFirst("img") : null;
    var imageSlug = imgEl ? imgEl.getSrc : "";
    var imageUrl = imageSlug.includes("http")
      ? imageSlug
      : `${this.source.baseUrl}${imageSlug}`;

    var pTag = detailsSection.select("p") || [];
    var description = pTag.length >= 2 ? pTag[pTag.length - 2].text.trim() : "";

    var status = 5;
    var genre = [];
    var author = "";
    var artist = "";

    pTag.forEach((p) => {
      var itemText = p.text.trim();
      if (itemText.includes("Genres:")) {
        genre = itemText.replace("Genres:", "").trim().split(", ");
      } else if (itemText.includes("Status:")) {
        var sts = itemText.replace("Status:", "").trim().split("\n")[0];
        status = statusCode(sts);
      } else if (itemText.includes("Writer:")) {
        author = itemText.replace("Writer:", "").trim();
      } else if (itemText.includes("Artist:")) {
        artist = itemText.replace("Artist:", "").trim();
      }
    });

    var chapters = [];
    var table = doc.selectFirst("table.listing") || doc.selectFirst("table");
    if (table) {
      var tr = table.select("tr") || [];
      if (tr.length > 2) {
        tr.splice(0, 2);
        tr.forEach((item) => {
          var tds = item.select("td");
          if (tds && tds.length > 0) {
            var aTag = tds[0].selectFirst("a");
            if (aTag) {
              var chapLink = aTag.getHref;
              var chapTitle = aTag.text.trim().replace(`${name} `, "");
              chapTitle = chapTitle[0] == "_" ? chapTitle.substring(1) : chapTitle;

              var uploadDate = tds[1] ? tds[1].text.trim() : "";
              var date = new Date(uploadDate);
              var dateUpload = isNaN(date.getTime()) ? Date.now().toString() : date.getTime().toString();

              chapters.push({ url: chapLink, name: chapTitle, dateUpload });
            }
          }
        });
      }
    }

    return {
      name,
      link: baseUrl + url,
      imageUrl,
      description,
      genre,
      status,
      author,
      artist,
      chapters,
    };
  }

  async getPageList(url) {
    var pages = [];
    var hdr = this.getHeaders();
    let match;
    var imageQuality = this.getPreference("readcomiconline_page_quality") || "h";

    var doc = await this.request(url);
    var html = doc.html;

    var baseUrlOverride = "";
    const hostRegex = /return\s+baeu\s*\(\s*l\s*,\s*'([^']+?)'\s*\);?/g;
    match = hostRegex.exec(html);
    if (match && match.length > 1) {
      baseUrlOverride = match[1];
      if (baseUrlOverride.slice(-1) != "/") baseUrlOverride += "/";
    }

    const pageRegex = /pht\s*=\s*'([^']+?)';?/g;
    while ((match = pageRegex.exec(html)) !== null) {
      var encodedImageUrl = match[1];
      var decodedImageUrl = this.decodeImageUrl(
        encodedImageUrl,
        imageQuality,
        baseUrlOverride
      );
      pages.push({
        url: decodedImageUrl,
        headers: hdr,
      });
    }
    return pages;
  }

  getFilterList() {
    function formateState(type_name, items, values) {
      var state = [];
      for (var i = 0; i < items.length; i++) {
        state.push({ type_name: type_name, name: items[i], value: values[i] });
      }
      return state;
    }

    var filters = [];
    var items = ["Action", "Adventure", "Comedy", "Drama", "Fantasy", "Horror", "Mystery", "Sci-Fi", "Superhero", "Thriller"];
    var values = ["1", "2", "3", "19", "20", "15", "23", "16", "22", "34"];

    filters.push({
      type_name: "GroupFilter",
      name: "Genres",
      state: formateState("CheckBox", items, values),
    });

    return filters;
  }

  getSourcePreferences() {
    return [
      {
        key: "readcomiconline_page_quality",
        listPreference: {
          title: "Preferred image quality",
          summary: "",
          valueIndex: 2,
          entries: ["Low", "Medium", "High", "Highest"],
          entryValues: ["l", "m", "h", "vh"],
        },
      },
    ];
  }

  base64UrlDecode(input) {
    let base64 = input.replace(/-/g, "+").replace(/_/g, "/");
    while (base64.length % 4 !== 0) {
      base64 += "=";
    }
    const base64abc = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    const outputBytes = [];

    for (let i = 0; i < base64.length; i += 4) {
      const c1 = base64abc.indexOf(base64[i]);
      const c2 = base64abc.indexOf(base64[i + 1]);
      const c3 = base64abc.indexOf(base64[i + 2]);
      const c4 = base64abc.indexOf(base64[i + 3]);
      const triplet = (c1 << 18) | (c2 << 12) | ((c3 & 63) << 6) | (c4 & 63);

      outputBytes.push((triplet >> 16) & 0xff);
      if (base64[i + 2] !== "=") outputBytes.push((triplet >> 8) & 0xff);
      if (base64[i + 3] !== "=") outputBytes.push(triplet & 0xff);
    }
    return String.fromCharCode(...outputBytes);
  }

  extractBeforeDecode(url) {
    return url.substring(15, 33) + url.substring(50);
  }

  finalizeDecodedString(decoded) {
    return (
      decoded.substring(0, decoded.length - 11) +
      decoded[decoded.length - 2] +
      decoded[decoded.length - 1]
    );
  }

  decoderFunction(encodedUrl) {
    var decodedUrl = this.extractBeforeDecode(encodedUrl);
    decodedUrl = this.finalizeDecodedString(decodedUrl);
    decodedUrl = decodeURIComponent(this.base64UrlDecode(decodedUrl));
    decodedUrl = decodedUrl.substring(0, 13) + decodedUrl.substring(17);
    return decodedUrl.slice(0, -2) + "=s1600";
  }

  decodeImageUrl(encodedImageUrl, imageQuality, baseUrlOverride) {
    var IMAGEQUALITY = [
      { "l": "900", "m": "0", "h": "1600", "vh": "2041" },
      { "l": "900", "m": "1600", "h": "2041", "vh": "0" },
    ];

    let finalUrl;
    var qType = 0;
    if (!encodedImageUrl.startsWith("https")) {
      encodedImageUrl = encodedImageUrl
        .replace(/6UUQS__ACd__/g, "b")
        .replace(/pw_.g28x/g, "b");

      var encodedUrl = encodedImageUrl.split("=s")[0];
      var decodedUrl = this.decoderFunction(encodedUrl);
      var queryParams = encodedImageUrl.substring(encodedImageUrl.indexOf("?"));
      finalUrl = baseUrlOverride + decodedUrl + queryParams;
    } else {
      qType = 1;
      finalUrl = baseUrlOverride + encodedImageUrl.split(".com/")[1];
    }
    return finalUrl.replace("s1600", `s${IMAGEQUALITY[qType][imageQuality] || "1600"}`);
  }
}
