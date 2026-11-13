import 'package:google_mobile_ads/google_mobile_ads.dart';

/// Google's public TEST units. Never substitute live production units for testing.
class TestAds {
  static const androidAppId = 'ca-app-pub-3940256099942544~3347511713';
  static const banner = 'ca-app-pub-3940256099942544/6300978111';
  static const interstitial = 'ca-app-pub-3940256099942544/1033173712';
}

class InterstitialCoordinator {
  InterstitialAd? _loaded;
  int _successfulExports = 0;
  bool _loading = false;
  bool _disposed = false;

  void preload() {
    if (_loading || _loaded != null || _disposed) return;
    _loading = true;
    InterstitialAd.load(
      adUnitId: TestAds.interstitial,
      request: const AdRequest(),
      adLoadCallback: InterstitialAdLoadCallback(
        onAdLoaded: (ad) {
          _loading = false;
          if (_disposed) { ad.dispose(); return; }
          _loaded = ad;
        },
        onAdFailedToLoad: (error) { _loading = false; },
      ),
    );
  }

  /// Only after successfully EXPORTING, and at most every fourth export.
  void onSuccessfulExport() {
    _successfulExports++;
    if (_successfulExports % 4 != 0) return;
    final ad = _loaded;
    if (ad == null || _disposed) return;
    _loaded = null;
    ad.fullScreenContentCallback = FullScreenContentCallback(
      onAdDismissedFullScreenContent: (ad) { ad.dispose(); preload(); },
      onAdFailedToShowFullScreenContent: (ad, error) { ad.dispose(); preload(); },
    );
    ad.show();
  }

  void dispose() {
    _disposed = true;
    _loaded?.dispose();
    _loaded = null;
  }
}
