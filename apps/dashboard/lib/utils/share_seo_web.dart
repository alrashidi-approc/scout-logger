import 'package:web/web.dart' as web;

const _suffix = ' | Scout Logger';
const _defaultDescription = 'Scout Logger Dashboard';

String? _savedTitle;

void applyShareSeo({required String title, required String description, required String url}) {
  _savedTitle ??= web.document.title;
  final fullTitle = '$title$_suffix';
  web.document.title = fullTitle;

  _setName('description', description);
  _setProperty('og:title', fullTitle);
  _setProperty('og:description', description);
  _setProperty('og:url', url);
  _setProperty('og:type', 'article');
  _setProperty('og:site_name', 'Scout Logger');
  _setName('twitter:card', 'summary');
  _setName('twitter:title', fullTitle);
  _setName('twitter:description', description);
  _setLink('canonical', url);
}

void clearShareSeo() {
  if (_savedTitle != null) {
    web.document.title = _savedTitle!;
    _savedTitle = null;
  }

  final desc = web.document.querySelector('meta[name="description"]') as web.HTMLMetaElement?;
  if (desc?.getAttribute('data-scout-seo') != null) {
    desc!
      ..content = _defaultDescription
      ..removeAttribute('data-scout-seo');
  }

  for (final name in ['twitter:card', 'twitter:title', 'twitter:description']) {
    web.document.querySelector('meta[name="$name"][data-scout-seo]')?.remove();
  }
  for (final property in ['og:title', 'og:description', 'og:url', 'og:type', 'og:site_name']) {
    web.document.querySelector('meta[property="$property"][data-scout-seo]')?.remove();
  }
  web.document.querySelector('link[rel="canonical"][data-scout-seo]')?.remove();
}

void _setName(String name, String content) {
  var el = web.document.querySelector('meta[name="$name"]') as web.HTMLMetaElement?;
  if (el == null) {
    el = web.document.createElement('meta') as web.HTMLMetaElement
      ..name = name
      ..setAttribute('data-scout-seo', '1');
    web.document.head?.append(el);
  } else {
    el.setAttribute('data-scout-seo', '1');
  }
  el.content = content;
}

void _setProperty(String property, String content) {
  var el = web.document.querySelector('meta[property="$property"]') as web.HTMLMetaElement?;
  if (el == null) {
    el = web.document.createElement('meta') as web.HTMLMetaElement
      ..setAttribute('property', property)
      ..setAttribute('data-scout-seo', '1');
    web.document.head?.append(el);
  } else {
    el.setAttribute('data-scout-seo', '1');
  }
  el.content = content;
}

void _setLink(String rel, String href) {
  var el = web.document.querySelector('link[rel="$rel"]') as web.HTMLLinkElement?;
  if (el == null) {
    el = web.document.createElement('link') as web.HTMLLinkElement
      ..rel = rel
      ..setAttribute('data-scout-seo', '1');
    web.document.head?.append(el);
  } else {
    el.setAttribute('data-scout-seo', '1');
  }
  el.href = href;
}
