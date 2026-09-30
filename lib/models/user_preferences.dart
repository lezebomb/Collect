class UserPreferences {
  const UserPreferences({
    this.showPrice = false,
    this.showOwnedDays = false,
    this.showDailyCost = false,
    this.wallpaperUrl,
  });

  final bool showPrice;
  final bool showOwnedDays;
  final bool showDailyCost;
  final String? wallpaperUrl;

  factory UserPreferences.fromJson(Map<String, dynamic> json) =>
      UserPreferences(
        showPrice: json['show_price'] == true,
        showOwnedDays: json['show_owned_days'] == true,
        showDailyCost: json['show_daily_cost'] == true,
        wallpaperUrl: json['wallpaper_url'] as String?,
      );

  Map<String, dynamic> toJson() => {
    'show_price': showPrice,
    'show_owned_days': showOwnedDays,
    'show_daily_cost': showDailyCost,
    'wallpaper_url': wallpaperUrl,
  };

  UserPreferences copyWith({
    bool? showPrice,
    bool? showOwnedDays,
    bool? showDailyCost,
    String? wallpaperUrl,
    bool clearWallpaper = false,
  }) => UserPreferences(
    showPrice: showPrice ?? this.showPrice,
    showOwnedDays: showOwnedDays ?? this.showOwnedDays,
    showDailyCost: showDailyCost ?? this.showDailyCost,
    wallpaperUrl: clearWallpaper ? null : (wallpaperUrl ?? this.wallpaperUrl),
  );
}
