/// Paths and URLs shared by the site header and footer.
abstract class SiteLinks {
  // In-app pages (registered in routes/app_router.dart).
  static const String privacy = '/privacy';
  static const String terms = '/terms';
  static const String refund = '/refund';
  static const String disclaimer = '/disclaimer';
  static const String feedback = '/feedback';

  // Association website (no custom domain yet).
  static const String website =
      'https://nitksaa-website-246773894709.asia-south1.run.app';
  static const String websiteAbout = '$website/about';

  static const String contactEmail = 'nitksaa.infra@gmail.com';
}
