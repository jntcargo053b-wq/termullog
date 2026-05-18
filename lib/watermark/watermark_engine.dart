// lib/watermark/watermark_engine.dart
import 'dart:isolate';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import '../core/constants.dart';
import 'watermark_params.dart';
import 'layouts/watermark_layout_base.dart';
import 'layouts/layout_film_strip.dart';
import 'layouts/layout_dslr_corner.dart';
import 'layouts/layout_cinematic.dart';
import 'layouts/layout_field_survey.dart';
import 'layouts/layout_hud.dart';
import 'layouts/layout_gps_card.dart';
import 'layouts/layout_polaroid.dart';
import 'layouts/layout_side_panel.dart';
import 'layouts/layout_cinematic_v2.dart';
import 'layouts/layout_timemark_style.dart';
import 'layouts/layout_nama_baru.dart'; // Modern Clean Card

class WatermarkEngine {
  static final Map<int, WatermarkLayoutBase> _layouts = {
    0: LayoutFilmStrip(),
    1: LayoutDSLRCorner(),       // dslrCorner
    2: LayoutCinematic(),
    3: LayoutFieldSurvey(),
    4: LayoutHUD(),
    5: LayoutGpsCard(),
    6: LayoutPolaroid(),
    7: LayoutSidePanel(),
    8: LayoutCinematicV2(),
    9: LayoutTimeMarkStyle(),
    10: LayoutNamaBaru(),        // modern (Modern Clean Card)
  };

  // ... (applyFromMap, createParams tetap)
