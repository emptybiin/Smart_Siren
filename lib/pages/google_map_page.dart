import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:location/location.dart' as loc; // loc 별칭 사용
import 'package:flutter_google_places/flutter_google_places.dart';
import 'package:google_maps_webservice/places.dart';
import 'package:http/http.dart' as http;
import 'package:smartsiren/constants.dart'; // Google Maps API 키 포함

class GoogleMapPage extends StatefulWidget {
  const GoogleMapPage({super.key});

  @override
  State<GoogleMapPage> createState() => _GoogleMapPageState();
}

class _GoogleMapPageState extends State<GoogleMapPage> {
  GoogleMapController? mapController;
  final loc.Location locationController = loc.Location(); // loc.Location 사용

  LatLng? departures;
  LatLng? arrivals;

  Map<PolylineId, Polyline> polylines = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await fetchLocationUpdates();
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(
          title: const Text('A.I SMART SIREN'),
          actions: [
            IconButton(
              icon: const Icon(Icons.search),
              onPressed: () async {
                departures = await _showPlacePicker();
                if (departures != null) {
                  arrivals = await _showPlacePicker();
                  if (arrivals != null) {
                    await fetchPolylinePoints();
                  }
                }
              },
            ),
          ],
        ),
        body: GoogleMap(
          initialCameraPosition: CameraPosition(
            target: departures ?? const LatLng(37.5452077, 127.0824639),
            zoom: 13,
          ),
          markers: _createMarkers(),
          polylines: Set<Polyline>.of(polylines.values),
          onMapCreated: (GoogleMapController controller) {
            mapController = controller;
          },
        ),
        floatingActionButton: FloatingActionButton(
          onPressed: _goToCurrentLocation,
          child: const Icon(Icons.my_location),
        ),
      );

  Future<LatLng?> _showPlacePicker() async {
    Prediction? p = await PlacesAutocomplete.show(
      context: context,
      apiKey: googleMapsApiKey,
      mode: Mode.fullscreen, //Mode.overlay
      language: 'kr',
      components: [new Component(Component.country, "kr")],
      decoration: InputDecoration(
        hintText: '장소 검색',
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
        contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 15),
      ),
    );

    if (p != null) {
      GoogleMapsPlaces _places = GoogleMapsPlaces(
        apiKey: googleMapsApiKey,
      );
      PlacesDetailsResponse detail =
          await _places.getDetailsByPlaceId(p.placeId!);

      // geometry나 location이 null인 경우를 처리
      if (detail.result.geometry?.location != null) {
        final lat = detail.result.geometry!.location.lat;
        final lng = detail.result.geometry!.location.lng;

        setState(() {
          mapController?.animateCamera(
            CameraUpdate.newLatLngZoom(LatLng(lat, lng), 14),
          );
        });

        return LatLng(lat, lng);
      } else {
        // geometry나 location이 null일 때의 처리
        print("위치 정보를 찾을 수 없습니다.");
      }
    } else {
      print("검색되지 않았습니다.");
    }
    return null;
  }

  Future<void> fetchLocationUpdates() async {
    bool serviceEnabled;
    loc.PermissionStatus permissionGranted; // loc.PermissionStatus 사용

    serviceEnabled = await locationController.serviceEnabled();
    if (!serviceEnabled) {
      serviceEnabled = await locationController.requestService();
      if (!serviceEnabled) return;
    }

    permissionGranted = await locationController.hasPermission();
    if (permissionGranted == loc.PermissionStatus.denied) {
      // loc.PermissionStatus 사용
      permissionGranted = await locationController.requestPermission();
      if (permissionGranted != loc.PermissionStatus.granted)
        return; // loc.PermissionStatus 사용
    }

    locationController.onLocationChanged.listen((loc.LocationData currentLocation) {
      if (currentLocation.latitude != null && currentLocation.longitude != null) {
        setState(() {
          departures = LatLng(currentLocation.latitude!, currentLocation.longitude!);
        });
      }
    });

  }

  Future<void> _goToCurrentLocation() async {
    final loc.LocationData currentLocation =
        await locationController.getLocation(); // loc.LocationData 사용
    mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(
          target: LatLng(currentLocation.latitude!, currentLocation.longitude!),
          zoom: 15,
        ),
      ),
    );
  }

  Future<void> fetchPolylinePoints() async {
    if (departures == null || arrivals == null) return;

    var response = await http.get(Uri.parse(
        "https://maps.googleapis.com/maps/api/directions/json?origin=${departures!.latitude},${departures!.longitude}&destination=${arrivals!.latitude},${arrivals!.longitude}&key=$googleMapsApiKey"));

    if (response.statusCode == 200) {
      Map data = jsonDecode(response.body);
      String encodedPoints = data['routes'][0]['overview_polyline']['points'];
      List<LatLng> polylineCoordinates = _decodePoly(encodedPoints);

      setState(() {
        polylines[PolylineId('overview_polyline')] = Polyline(
          polylineId: PolylineId('overview_polyline'),
          color: Colors.blue,
          points: polylineCoordinates,
          width: 5,
        );
      });
    }
  }

  Set<Marker> _createMarkers() {
    Set<Marker> markers = {};

    if (departures != null) {
      markers.add(Marker(
        markerId: const MarkerId('departures'),
        position: departures!,
      ));
    }

    if (arrivals != null) {
      markers.add(Marker(
        markerId: const MarkerId('arrivals'),
        position: arrivals!,
      ));
    }

    return markers;
  }

  List<LatLng> _decodePoly(String encoded) {
    List<LatLng> poly = [];
    int index = 0, len = encoded.length;
    int lat = 0, lng = 0;

    while (index < len) {
      int b, shift = 0, result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlat = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lat += dlat;

      shift = 0;
      result = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result |= (b & 0x1f) << shift;
        shift += 5;
      } while (b >= 0x20);
      int dlng = ((result & 1) != 0 ? ~(result >> 1) : (result >> 1));
      lng += dlng;

      LatLng p = LatLng((lat / 1E5).toDouble(), (lng / 1E5).toDouble());
      poly.add(p);
    }

    return poly;
  }
}
