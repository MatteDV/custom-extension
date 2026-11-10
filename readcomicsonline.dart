import 'package:mangayomi/bridge_lib.dart';

void main(List<String> args) {
  DefaultExtension();
}

const mangayomiSources = [
  {
    "name": "ReadComicOnline Custom",
    "lang": "en",
    "baseUrl": "https://readcomicsonline.ru",
    "apiUrl": "",
    "iconUrl": "https://www.google.com/s2/favicons?sz=256&domain=https://readcomicsonline.ru/",
    "typeSource": "single",
    "itemType": 0,
    "version": "0.3.1",
    "pkgPath": "readcomicsonline.dart"
  }
];

class DefaultExtension extends MProvider {
  String get getBaseUrl {
    try {
      if (source != null && source.baseUrl != null && source.baseUrl.isNotEmpty) {
        var bUrl = source.baseUrl;
        if (bUrl.endsWith("/")) {
          bUrl = bUrl.substring(0, bUrl.length - 1);
        }
        return bUrl;
      }
    } catch (_) {}
    return "https://readcomicsonline.ru";
  }

  @override
  Map<String, String> getHeaders() {
    String baseUrl = getBaseUrl;
    return {
      "User-Agent":
          "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
      "Referer": "$baseUrl/",
      "Origin": baseUrl,
      "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
      "Accept-Language": "en-US,en;q=0.9",
    };
  }

  Future<dynamic> request(String slug) async {
    String baseUrl = getBaseUrl;
    String url = slug;
    if (!url.startsWith("/")) {
      url = "/$url";
    }
    if (!url.contains(baseUrl)) {
      url = "$baseUrl$url";
    }
    var res = await Client().get(Uri.parse(url), getHeaders());
    return parseHtml(res.body);
  }

  Future<MPages> getListPage(String slug, int page) async {
    String url = slug;
    if (slug.contains("?")) {
      url = "$slug&page=$page";
    } else if (slug != "/" && slug != "") {
      url = "$slug?page=$page";
    }
    
    var doc = await request(url);
    String baseUrl = getBaseUrl;
    List<MManga> list = [];

    var comicList = doc.select(".list-comic .item");
    if (comicList.isEmpty) comicList = doc.select(".group-item");
    if (comicList.isEmpty) comicList = doc.select(".item");

    if (comicList.isNotEmpty) {
      for (var item in comicList) {
        var titleEl = item.selectFirst(".title") ?? item.selectFirst("a.title") ?? item.selectFirst("a");
        String name = (titleEl != null && titleEl.text != null) ? titleEl.text.trim() : "";

        var linkEl = item.selectFirst("a");
        String link = linkEl != null ? (linkEl.getHref ?? "") : "";

        var imgEl = item.selectFirst("img");
        String imageSlug = imgEl != null ? (imgEl.getSrc ?? "") : "";
        String imageUrl = imageSlug.contains("http")
            ? imageSlug
            : "$baseUrl$imageSlug";

        if (name.isNotEmpty && link.isNotEmpty) {
          MManga manga = MManga();
          manga.name = name;
          manga.link = link;
          manga.imageUrl = imageUrl;
          list.add(manga);
        }
      }
    }

    // Fallback: cerca tutti i link ai fumetti se la lista principale risulta vuota
    if (list.isEmpty) {
      var allLinks = doc.select("a");
      Set<String> addedLinks = {};

      for (var a in allLinks) {
        String link = a.getHref ?? "";
        String name = a.text != null ? a.text.trim() : "";
        
        if (link.contains("/Comic/") && !addedLinks.contains(link) && name.length > 1) {
          addedLinks.add(link);
          
          var parent = a.parent;
          var imgEl = parent != null ? parent.selectFirst("img") : null;
          String imageSlug = imgEl != null ? (imgEl.getSrc ?? "") : "";
          String imageUrl = imageSlug.contains("http")
              ? imageSlug
              : "$baseUrl$imageSlug";

          MManga manga = MManga();
          manga.name = name;
          manga.link = link;
          manga.imageUrl = imageUrl;
          list.add(manga);
        }
      }
    }

    var pager = doc.select("ul.pager > li, .pagination > li");
    bool hasNextPage = false;
    if (pager.isNotEmpty && pager.last != null && pager.last.text != null) {
      String lastText = pager.last.text.trim();
      hasNextPage = lastText.contains("Last") || lastText.contains("Next") || lastText.contains(">");
    }

    return MPages(list, hasNextPage);
  }

  @override
  Future<MPages> getPopular(int page) async {
    return await getListPage("/ComicList/MostPopular", page);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    return await getListPage("/ComicList/LatestUpdate", page);
  }

  @override
  Future<MPages> search(String query, int page, List<dynamic> filters) async {
    if (query.isNotEmpty) {
      String slug = "/AdvanceSearch?comicName=${Uri.encodeComponent(query)}";
      return await getListPage(slug, page);
    }
    return await getListPage("/ComicList/MostPopular", page);
  }

  @override
  Future<MManga> getDetail(String url) async {
    int statusCode(String status) {
      if (status == "Ongoing") return 0;
      if (status == "Completed") return 1;
      return 5;
    }

    String baseUrl = getBaseUrl;
    String cleanUrl = url;
    if (cleanUrl.contains(baseUrl)) {
      cleanUrl = cleanUrl.replaceAll(baseUrl, "");
    }

    var doc = await request(cleanUrl);
    var detailsSection = doc.selectFirst(".barContent") ?? doc.selectFirst(".bigBarContainer");
    if (detailsSection == null) {
      throw Exception("Impossibile caricare i dettagli (Cloudflare)");
    }

    var nameEl = detailsSection.selectFirst("a");
    String name = (nameEl != null && nameEl.text != null) ? nameEl.text.trim() : "Unknown";

    var rightBox = doc.selectFirst(".rightBox") ?? doc.selectFirst(".col-md-3");
    var imgEl = rightBox != null ? rightBox.selectFirst("img") : null;
    String imageSlug = imgEl != null ? (imgEl.getSrc ?? "") : "";
    String imageUrl = imageSlug.contains("http")
        ? imageSlug
        : "$baseUrl$imageSlug";

    var pTag = detailsSection.select("p");
    String description = "";
    if (pTag.length >= 2 && pTag[pTag.length - 2] != null && pTag[pTag.length - 2].text != null) {
      description = pTag[pTag.length - 2].text.trim();
    }

    int status = 5;
    List<String> genre = [];
    String author = "";
    String artist = "";

    for (var p in pTag) {
      if (p != null && p.text != null) {
        String itemText = p.text.trim();
        if (itemText.contains("Genres:")) {
          genre = itemText.replaceAll("Genres:", "").trim().split(", ");
        } else if (itemText.contains("Status:")) {
          String sts = itemText.replaceAll("Status:", "").trim().split("\n")[0];
          status = statusCode(sts);
        } else if (itemText.contains("Writer:")) {
          author = itemText.replaceAll("Writer:", "").trim();
        } else if (itemText.contains("Artist:")) {
          artist = itemText.replaceAll("Artist:", "").trim();
        }
      }
    }

    List<MChapter> chapters = [];
    var table = doc.selectFirst("table.listing") ?? doc.selectFirst("table");
    if (table != null) {
      var tr = table.select("tr");
      for (var item in tr) {
        if (item != null) {
          var tds = item.select("td");
          if (tds.isNotEmpty && tds[0] != null) {
            var aTag = tds[0].selectFirst("a");
            if (aTag != null) {
              String chapLink = aTag.getHref ?? "";
              String rawTitle = aTag.text != null ? aTag.text.trim() : "";
              String chapTitle = rawTitle.replaceAll("$name ", "");
              if (chapTitle.startsWith("_")) {
                chapTitle = chapTitle.substring(1);
              }

              String uploadDate = (tds.length > 1 && tds[1] != null && tds[1].text != null) ? tds[1].text.trim() : "";
              DateTime? date = DateTime.tryParse(uploadDate);
              String dateUpload = date != null
                  ? date.millisecondsSinceEpoch.toString()
                  : DateTime.now().millisecondsSinceEpoch.toString();

              MChapter chapter = MChapter();
              chapter.url = chapLink;
              chapter.name = chapTitle;
              chapter.dateUpload = dateUpload;
              chapters.add(chapter);
            }
          }
        }
      }
    }

    MManga manga = MManga();
    manga.name = name;
    manga.link = "$baseUrl$cleanUrl";
    manga.imageUrl = imageUrl;
    manga.description = description;
    manga.genre = genre;
    manga.status = status;
    manga.author = author;
    manga.artist = artist;
    manga.chapters = chapters;

    return manga;
  }

  @override
  Future<List<String>> getPageList(String url) async {
    List<String> pages = [];
    var doc = await request(url);
    String html = doc.outerHtml ?? "";

    String baseUrlOverride = "";
    RegExp hostRegex = RegExp(r"return\s+baeu\s*\(\s*l\s*,\s*'([^']+?)'\s*\);?");
    var hostMatch = hostRegex.firstMatch(html);
    if (hostMatch != null && hostMatch.groupCount >= 1) {
      baseUrlOverride = hostMatch.group(1) ?? "";
      if (baseUrlOverride.isNotEmpty && !baseUrlOverride.endsWith("/")) {
        baseUrlOverride += "/";
      }
    }

    RegExp pageRegex = RegExp(r"pht\s*=\s*'([^']+?)';?");
    Iterable<RegExpMatch> matches = pageRegex.allMatches(html);
    for (var match in matches) {
      String? encodedImageUrl = match.group(1);
      if (encodedImageUrl != null && encodedImageUrl.isNotEmpty) {
        String decodedImageUrl = decodeImageUrl(encodedImageUrl, baseUrlOverride);
        pages.add(decodedImageUrl);
      }
    }
    return pages;
  }

  String decodeImageUrl(String encodedImageUrl, String baseUrlOverride) {
    if (!encodedImageUrl.startsWith("https")) {
      String cleaned = encodedImageUrl
          .replaceAll("6UUQS__ACd__", "b")
          .replaceAll("pw_.g28x", "b");
      String encodedUrl = cleaned.split("=s")[0];
      String decodedUrl = decoderFunction(encodedUrl);
      int queryIdx = cleaned.indexOf("?");
      String queryParams = queryIdx != -1 ? cleaned.substring(queryIdx) : "";
      return "$baseUrlOverride$decodedUrl$queryParams";
    }
    return "$baseUrlOverride${encodedImageUrl.split('.com/')[1]}";
  }

  String decoderFunction(String encodedUrl) {
    String decodedUrl = extractBeforeDecode(encodedUrl);
    decodedUrl = finalizeDecodedString(decodedUrl);
    decodedUrl = Uri.decodeComponent(base64UrlDecode(decodedUrl));
    decodedUrl = decodedUrl.substring(0, 13) + decodedUrl.substring(17);
    return "${decodedUrl.substring(0, decodedUrl.length - 2)}=s1600";
  }

  String extractBeforeDecode(String url) {
    if (url.length < 50) return url;
    return url.substring(15, 33) + url.substring(50);
  }

  String finalizeDecodedString(String decoded) {
    if (decoded.length < 11) return decoded;
    return decoded.substring(0, decoded.length - 11) +
        decoded[decoded.length - 2] +
        decoded[decoded.length - 1];
  }

  String base64UrlDecode(String input) {
    String base64 = input.replaceAll('-', '+').replaceAll('_', '/');
    while (base64.length % 4 != 0) {
      base64 += '=';
    }
    return String.fromCharCodes(base64Decode(base64));
  }
}
