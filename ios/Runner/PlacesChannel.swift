import Flutter
import MapKit

/// «قريب منك» على iOS: صيدليات ودكاترة من خرايط أبل، **من الجهاز نفسه**.
///
/// الجانب الدارت (`AppleMapKitPlaces` في `lib/data/places/places.dart`) بينادي
/// `nearby` بـ{lat, lon, radiusMeters} وبياخد قايمة صفوف:
///   { id, kind: "pharmacy" | "doctor" | "hospital" | "lab", name, lat, lon, phone }
///
/// * الصيدليات والدكاترة والمعامل: `MKLocalSearch` باستعلام بلغة طبيعية
///   («صيدلية»، «دكتور»، «معمل تحاليل») جوّه منطقة نصف قطرها الراديوس.
/// * المستشفيات: `MKLocalPointsOfInterestRequest` بفئة `.hospital` — فئة
///   بالظبط، مش كلمة بتتفسّر.
/// * وبعد الاتنين **فلترة بالمسافة** لأن MapKit بيرجّع اللي حوالين المنطقة
///   مش اللي جوّاها بس.
/// * مفيش مفتاح ولا MapKit JS: النظام هو اللي بيكلّم أبل، بنفس قواعد تطبيق
///   الخرايط نفسه. الموقع اللي بيطلع هو النقطة المقرّبة اللي دارت بعتتها.
/// * المعرّف: `MKMapItem.identifier` (iOS 18+)، وقبلها الإحداثيات — ثابت
///   كفاية لمفتاح في قايمة.
/// * **مفيش مواعيد فتح** — MapKit ما بيدّيهاش، فما بنبعتش الحقل أصلاً،
///   ودارت بتسيبه null والشاشة بتسكت.
/// * مفيش تقييمات: ولا الجانب ده ولا التاني عنده تقييم يتعرض.
///
/// الملف ده **ما يتختبرش من `flutter test`** — يتأكد على الآيفون.
final class PlacesChannel {
  static let name = "fakkarni/places"

  static func register(with messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: name, binaryMessenger: messenger)
    channel.setMethodCallHandler { call, result in
      guard call.method == "nearby" else {
        result(FlutterMethodNotImplemented)
        return
      }
      guard let args = call.arguments as? [String: Any],
            let lat = args["lat"] as? Double,
            let lon = args["lon"] as? Double,
            let radius = (args["radiusMeters"] as? NSNumber)?.doubleValue
      else {
        result(FlutterError(code: "bad_args", message: "nearby needs lat, lon, radiusMeters", details: nil))
        return
      }
      Task {
        do {
          let rows = try await nearby(lat: lat, lon: lon, radius: radius)
          result(rows)
        } catch {
          result(FlutterError(code: "mapkit", message: String(describing: error), details: nil))
        }
      }
    }
  }

  /// أربع طلبات بالتوازي، وبعدين دمج من غير تكرار (نفس المكان ممكن يرجع في
  /// اتنين — عيادة اسمها فيه «صيدلية»). أول نوع بيشوفه هو اللي بيثبت.
  private static func nearby(lat: Double, lon: Double, radius: Double) async throws -> [[String: Any]] {
    let center = CLLocationCoordinate2D(latitude: lat, longitude: lon)
    let region = MKCoordinateRegion(center: center, latitudinalMeters: radius * 2, longitudinalMeters: radius * 2)
    let here = CLLocation(latitude: lat, longitude: lon)

    async let pharmacies = search("صيدلية", kind: "pharmacy", region: region)
    async let doctors = search("دكتور", kind: "doctor", region: region)
    async let hospitals = pointsOfInterest(.hospital, kind: "hospital", center: center, radius: radius)
    async let labs = search("معمل تحاليل", kind: "lab", region: region)
    let items = try await pharmacies + doctors + hospitals + labs

    var seen = Set<String>()
    var rows: [[String: Any]] = []
    for (item, kind) in items {
      let coordinate = item.placemark.coordinate
      let distance = here.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
      guard distance <= radius else { continue }

      let id: String
      if #available(iOS 18.0, *), let identifier = item.identifier {
        id = "mapkit/\(identifier.rawValue)"
      } else {
        id = "mapkit/\(coordinate.latitude),\(coordinate.longitude)"
      }
      guard seen.insert(id).inserted else { continue }

      var row: [String: Any] = [
        "id": id,
        "kind": kind,
        "lat": coordinate.latitude,
        "lon": coordinate.longitude,
      ]
      if let name = item.name, !name.isEmpty { row["name"] = name }
      if let phone = item.phoneNumber, !phone.isEmpty { row["phone"] = phone }
      rows.append(row)
    }
    return rows
  }

  /// فئة MapKit بالظبط — للمستشفيات، اللي ليها فئة رسمية.
  private static func pointsOfInterest(
    _ category: MKPointOfInterestCategory, kind: String, center: CLLocationCoordinate2D, radius: Double
  ) async throws -> [(MKMapItem, String)] {
    let request = MKLocalPointsOfInterestRequest(center: center, radius: radius)
    request.pointOfInterestFilter = MKPointOfInterestFilter(including: [category])
    let response = try await MKLocalSearch(request: request).start()
    return response.mapItems.map { ($0, kind) }
  }

  private static func search(_ query: String, kind: String, region: MKCoordinateRegion) async throws -> [(MKMapItem, String)] {
    let request = MKLocalSearch.Request()
    request.naturalLanguageQuery = query
    request.region = region
    request.resultTypes = .pointOfInterest
    let response = try await MKLocalSearch(request: request).start()
    return response.mapItems.map { ($0, kind) }
  }
}
