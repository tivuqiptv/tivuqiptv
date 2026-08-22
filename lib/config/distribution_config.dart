class DistributionConfig {
  const DistributionConfig._();

  static const bool isAmazonAppstore = bool.fromEnvironment(
    'AMAZON_APPSTORE_BUILD',
  );
}
