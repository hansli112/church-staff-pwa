enum ServiceType {
  sundayService, // 主日
  youth, // 青崇
  children, // 兒主
}

extension ServiceTypeExtension on ServiceType {
  String get label {
    switch (this) {
      case ServiceType.sundayService:
        return '主日';
      case ServiceType.youth:
        return '青崇';
      case ServiceType.children:
        return '兒主';
    }
  }
}
