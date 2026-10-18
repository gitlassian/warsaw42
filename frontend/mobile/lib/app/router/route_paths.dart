abstract final class RoutePaths {
  static const map = '/';
  static const aeds = '/aeds';
  static const aed = '/aed/:id';
  static const navigate = '/aed/:id/navigate';
  static const report = '/report/:id';
  static const coverage = '/coverage';
  static const placement = '/placement';

  static String aedPath(String id) => '/aed/$id';
  static String navigatePath(String id) => '/aed/$id/navigate';
  static String reportPath(String id) => '/report/$id';
}
