import 'package:mangayomi/bridge_lib.dart';

const mangayomiSources = [
  {
    "name": "ReadComicsOnline Custom",
    "lang": "en",
    "baseUrl": "https://readcomicsonline.ru",
    "apiUrl": "",
    "iconUrl": "https://www.google.com/s2/favicons?sz=256&domain=https://readcomicsonline.ru/",
    "typeSource": "single",
    "itemType": 0,
    "version": "0.1.7",
    "pkgPath": "readcomicsonline.dart"
  }
];

class DefaultExtension extends MProvider {
  @override
  Map<String, String> getHeaders() {
    return {
      "User-Agent":
          "Mozilla/5.0 (iPhone; CPU iPhone OS 17_5 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.5 Mobile/15E148 Safari/604.1",
      "Referer": "${source.baseUrl}/",
      "Origin": source.baseUrl,
    };
  }

  Future<Document> request(String slug) async {
    String url = slug;
    String baseUrl = source.baseUrl;
    if (!slug.contains(baseUrl)) {
      url = baseUrl + slug;
    }
    var res = await Client().get(Uri.parse(url), getHeaders());
    return parseHtml(res.body);
  }

  Future<MPages> getListPage(String slug, int page) async {
    String url = "$slug page=$page";
    Document doc = await request(url);
    String baseUrl = source.baseUrl;
    List<MManga> list = [];

    List<Element> comicList = doc.select(".list-comic > .item");
    if (comicList.isEmpty) {
      comicList = doc.select(".group-item");
    }

    for (var item in comicList) {
      Element? titleEl = item.selectFirst(".title") ?? item.selectFirst("a");
      String name = titleEl != null ? titleEl.text.trim() : "";

      Element? linkEl = item.selectFirst("a");
      String link = linkEl != null ? linkEl.getHref : "";

      Element? imgEl = item.selectFirst("img");
      String imageSlug = imgEl != null ? imgEl.getSrc : "";
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

    List<Element> pager = doc.select("ul.pager > li");
    bool hasNextPage = false;
    if (pager.isNotEmpty) {
      String lastText = pager.last.text;
      hasNextPage = lastText.contains("Last") || lastText.contains("Next");
    }

    return MPages(list, hasNextPage);
  }

  @override
  Future<MPages> getPopular(int page) async {
    return await getListPage("/ComicList/MostPopular?", page);
  }

  @override
  Future<MPages> getLatestUpdates(int page) async {
    return await getListPage("/ComicList/LatestUpdate?", page);
  }

  @override
  Future<MPages> search(String query, int page, List<dynamic> filters) async {
    String genre = "";
    if (filters.isNotEmpty && filters[0].state != null) {
      List<String> selected = [];
      for (var item in filters[0].state) {
        if (item.state == true) {
          selected.add(item.value.toString());
        }
      }
      genre = selected.join(",");
    }

    String status = (filters.length > 1 && filters[1].values != null)
        ? filters[1].values[filters[1].state].value
        : "";
    String year = (filters.length > 2 && filters[2].values != null)
        ? filters[2].values[filters[2].state].value
        : "";

    String slug =
        "/AdvanceSearch?comicName=${Uri.encodeComponent(query)}&ig=${Uri.encodeComponent(genre)}&status=$status&pubDate=$year&";

    return await getListPage(slug, page);
  }

  @override
  Future<MManga> getDetail(String url) async {
    int statusCode(String status) {
      if (status == "Ongoing") return 0;
      if (status == "Completed") return 1;
      return 5;
    }

    String baseUrl = source.baseUrl;
    String cleanUrl = url;
    if (cleanUrl.contains(baseUrl)) {
      cleanUrl = cleanUrl.replaceAll(baseUrl, "");
    }

    Document doc = await request(cleanUrl);
    Element? detailsSection = doc.selectFirst(".barContent");
    if (detailsSection == null) {
      throw Exception("Impossibile caricare i dettagli (Cloudflare)");
    }

    Element? nameEl = detailsSection.selectFirst("a");
    String name = nameEl != null ? nameEl.text.trim() : "Unknown";

    Element? rightBox = doc.selectFirst(".rightBox");
    Element? imgEl = rightBox != null ? rightBox.selectFirst("img") : null;
    String imageSlug = imgEl != null ? imgEl.getSrc : "";
    String imageUrl = imageSlug.contains("http")
        ? imageSlug
        : "$baseUrl$imageSlug";

    List<Element> pTag = detailsSection.select("p");
    String description =
        pTag.length >= 2 ? pTag[pTag.length - 2].text.trim() : "";

    int status = 5;
    List<String> genre = [];
    String author = "";
    String artist = "";

    for (var p in pTag) {
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

    List<MChapter> chapters = [];
    Element? table = doc.selectFirst("table.listing") ?? doc.selectFirst("table");
    if (table != null) {
      List<Element> tr = table.select("tr");
      if (tr.length > 2) {
        tr.removeRange(0, 2);
        for (var item in tr) {
          List<Element> tds = item.select("td");
          if (tds.isNotEmpty) {
            Element? aTag = tds[0].selectFirst("a");
            if (aTag != null) {
              String chapLink = aTag.getHref;
              String chapTitle = aTag.text.trim().replaceAll("$name ", "");
              if (chapTitle.startsWith("_")) {
                chapTitle = chapTitle.substring(1);
              }

              String uploadDate = tds.length > 1 ? tds[1].text.trim() : "";
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
    Document doc = await request(url);
    String html = doc.outerHtml;

    String baseUrlOverride = "";
    RegExp hostRegex = RegExp(r"return\s+baeu\s*\(\s*l\s*,\s*'([^']+?)'\s*\);?");
    var hostMatch = hostRegex.firstMatch(html);
    if (hostMatch != null && hostMatch.groupCount >= 1) {
      baseUrlOverride = hostMatch.group(1)!;
      if (!baseUrlOverride.endsWith("/")) {
        baseUrlOverride += "/";
      }
    }

    RegExp pageRegex = RegExp(r"pht\s*=\s*'([^']+?)';?");
    Iterable<RegExpMatch> matches = pageRegex.allMatches(html);
    for (var match in matches) {
      String? encodedImageUrl = match.group(1);
      if (encodedImageUrl != null) {
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
    return url.substring(15, 33) + url.substring(50);
  }

  String finalizeDecodedString(String decoded) {
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
