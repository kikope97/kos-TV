/// Where the home rows are kept between starts: a file on the devices, the
/// browser's local storage on the web. See [HomeRowCacheStore].
library;

export 'home_row_cache_storage_io.dart'
    if (dart.library.js_interop) 'home_row_cache_storage_web.dart';
