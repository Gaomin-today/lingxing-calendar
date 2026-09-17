# LunarSwift runtime

Source: https://github.com/6tail/lunar-swift

Version: 1.1.8, fixed commit `a7ec0e9b29f84a5d98b09b9ffd31145f17470d56`.

License: MIT, Copyright (c) 2023 6tail; full license is in `LICENSE`.

All files under `Sources` are copied unchanged from that commit. `Package.swift`
is reduced to the runtime library product; upstream tests and documentation are
not copied. No network dependency resolution is needed to build the app.

The application's four-pillar engine remains responsible for absolute solar-term
boundaries, civil time zones and configurable day boundaries. This library's
tables supply deterministic chart details. Its minute-based `Yun` (sect 2)
conversion is adapted in `LuckCycleEngine` to use absolute intervals and the
profile's IANA calendar, rather than treating overseas local fields as Beijing
astronomical time. Ten-year intervals are half-open, with no lost final day.
