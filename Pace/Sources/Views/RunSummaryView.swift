import SwiftUI
import SwiftData
import MapKit
import Charts

/// Post-run recap: the route drawn on a map zoomed to fit it, plus the numbers.
/// Shown right after a run finishes (with a Done button) and from History.
struct RunSummaryView: View {
    let run: Run
    var title: String?
    var onDone: (() -> Void)?

    @Query(sort: \PlannedSession.scheduledAt) private var sessions: [PlannedSession]
    @Query(sort: \Run.startedAt) private var runs: [Run]

    private var session: PlannedSession? {
        guard let id = run.plannedSessionID else { return nil }
        return sessions.first { $0.id == id }
    }

    private var insights: [RunInsight] {
        let session = session
        return RunInsights.notes(
            for: run,
            session: session,
            previousRuns: runs.filter { $0.startedAt < run.startedAt },
            weekSessions: session.map { TrainingAnalyzer.currentBlock(week: $0.week, of: sessions) } ?? [],
            nextSession: sessions.first { $0.state == .planned },
            isFresh: onDone != nil
        )
    }

    var body: some View {
        ZStack {
            Theme.background.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    header
                    if !insights.isEmpty {
                        InsightsCard(insights: insights)
                    }
                    if let note = session?.adjustmentNote {
                        AdjustmentCard(note: note)
                    }
                    RouteMap(points: run.routePoints)
                        .frame(height: 340)
                        .clipShape(RoundedRectangle(cornerRadius: 24))
                    statsGrid
                    if let samples = run.heartRateSamples, samples.count >= 2 {
                        HeartRateCard(samples: samples, segments: run.segments ?? [], average: run.averageHeartRate, max: run.maxHeartRate)
                    }
                    if let segments = run.segments, !segments.isEmpty {
                        SegmentsCard(segments: segments)
                    }
                    if let onDone {
                        Button(action: onDone) {
                            Text("DONE")
                                .font(.headline.weight(.black))
                                .foregroundStyle(Theme.onAccent)
                                .frame(maxWidth: .infinity)
                                .padding(20)
                                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 18))
                        }
                        .padding(.top, 6)
                    }
                }
                .padding(24)
            }
        }
        .foregroundStyle(Theme.text)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(onDone != nil ? "SESSION COMPLETE" : run.startedAt.formatted(.dateTime.weekday(.wide).day().month(.wide)).uppercased())
                .font(.caption.weight(.bold))
                .tracking(1.4)
                .foregroundStyle(Theme.accent)
            Text((title ?? run.sessionKind.label).uppercased())
                .font(.system(size: 34, weight: .black, design: .rounded))
        }
    }

    private var statsGrid: some View {
        Grid(horizontalSpacing: 12, verticalSpacing: 12) {
            GridRow {
                StatTile(value: Format.kilometers(run.distanceMeters), unit: "KM", label: "DISTANCE")
                StatTile(value: Format.clock(run.duration), unit: nil, label: "TIME")
            }
            GridRow {
                StatTile(value: Format.pace(seconds: run.duration, meters: run.distanceMeters), unit: "/KM", label: "AVG PACE")
                StatTile(value: run.startedAt.formatted(date: .omitted, time: .shortened), unit: nil, label: "STARTED")
            }
            if let average = run.averageHeartRate {
                GridRow {
                    StatTile(value: "\(Int(average.rounded()))", unit: "BPM", label: "AVG HEART RATE")
                    StatTile(value: run.maxHeartRate.map { "\(Int($0.rounded()))" } ?? "—", unit: "BPM", label: "MAX HEART RATE")
                }
            }
        }
    }
}

/// The recap's human part: milestones, where the week stands, what's next.
private struct InsightsCard: View {
    let insights: [RunInsight]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(insights) { insight in
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Image(systemName: insight.symbol)
                        .font(.subheadline.weight(.bold))
                        .foregroundStyle(insight.kind == .milestone ? Theme.accent : Theme.secondaryText)
                        .frame(width: 22)
                    Text(insight.text)
                        .font(insight.kind == .milestone ? .body.weight(.semibold) : .body)
                        .foregroundStyle(insight.kind == .milestone ? Theme.text : Theme.text.opacity(0.78))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
    }
}

/// Shown when the weekly check changed this session before it was run.
struct AdjustmentCard: View {
    let note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("THIS SESSION WAS ADJUSTED", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(Theme.accent)
            Text(note)
                .font(.subheadline)
                .foregroundStyle(Theme.text.opacity(0.78))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .overlay(RoundedRectangle(cornerRadius: 20).stroke(Theme.accent.opacity(0.4), lineWidth: 1))
    }
}

/// Every interval as it was actually run: duration, distance, pace and, for
/// Watch runs, heart rate, with a bar comparing its speed to the fastest
/// segment so fading or pacing shows at a glance.
/// Heart rate over the run, drawn over the intervals it happened in: faint
/// bands in each interval's color, and the same colors as a strip along the
/// bottom, so the line visibly climbs through runs and settles in walks.
private struct HeartRateCard: View {
    let samples: [HeartRateSample]
    let segments: [RecordedSegment]
    let average: Double?
    let max: Double?

    private static let lineColor = Color(red: 1.0, green: 0.32, blue: 0.38)

    /// A little headroom around the readings so the line never touches the edges.
    private var domain: ClosedRange<Double> {
        let values = samples.map(\.beatsPerMinute)
        let low = ((values.min() ?? 60) - 12) / 10
        let high = ((values.max() ?? 180) + 6) / 10
        return (low.rounded(.down) * 10)...(high.rounded(.up) * 10)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("HEART RATE")
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.accent)
                Spacer()
                if let average, let max {
                    Text("AVG \(Int(average.rounded())) · MAX \(Int(max.rounded())) BPM")
                        .font(.caption.weight(.black).monospacedDigit())
                        .tracking(0.6)
                        .foregroundStyle(Self.lineColor)
                }
            }

            Chart {
                let domain = domain
                let strip = (domain.upperBound - domain.lowerBound) * 0.05
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    RectangleMark(xStart: .value("Start", segment.startedAt), xEnd: .value("End", segment.endedAt))
                        .foregroundStyle(segment.kind.color.opacity(0.12))
                    RectangleMark(
                        xStart: .value("Start", segment.startedAt),
                        xEnd: .value("End", segment.endedAt),
                        yStart: .value("BPM", domain.lowerBound),
                        yEnd: .value("BPM", domain.lowerBound + strip)
                    )
                    .foregroundStyle(segment.kind.color)
                }
                ForEach(samples, id: \.timestamp) { sample in
                    LineMark(x: .value("Time", sample.timestamp), y: .value("BPM", sample.beatsPerMinute))
                        .interpolationMethod(.catmullRom)
                        .lineStyle(StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                        .foregroundStyle(Self.lineColor)
                }
            }
            .chartYScale(domain: domain)
            .chartXAxis(.hidden)
            .chartYAxis {
                AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { _ in
                    AxisGridLine().foregroundStyle(Theme.text.opacity(0.08))
                    AxisValueLabel()
                        .font(.caption2.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            .frame(height: 130)
            .accessibilityLabel("Heart rate over the run")
            .accessibilityValue(average.map { "Average \(Int($0.rounded())) beats per minute" } ?? "")
        }
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
    }
}

private struct SegmentsCard: View {
    let segments: [RecordedSegment]

    private var showsHeartRate: Bool { segments.contains { $0.averageHeartRate != nil } }

    private var maxSpeed: Double {
        segments.map { $0.distanceMeters / max($0.activeDuration, 1) }.max() ?? 0
    }

    private var runSummary: (time: TimeInterval, meters: Double)? {
        let runs = segments.filter { $0.kind == .run }
        guard !runs.isEmpty else { return nil }
        return (runs.reduce(0) { $0 + $1.activeDuration }, runs.reduce(0) { $0 + $1.distanceMeters })
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                Text("INTERVALS")
                    .font(.caption.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(Theme.accent)
                Spacer()
                if let runSummary {
                    Text("RUNNING \(Format.pace(seconds: runSummary.time, meters: runSummary.meters)) /KM")
                        .font(.caption.weight(.black).monospacedDigit())
                        .tracking(0.6)
                        .foregroundStyle(IntervalKind.run.color)
                }
            }

            HStack(spacing: 10) {
                Spacer()
                Text("TIME").frame(width: 48, alignment: .trailing)
                Text("KM").frame(width: 40, alignment: .trailing)
                Text("/KM").frame(width: 52, alignment: .trailing)
                if showsHeartRate {
                    Text("BPM").frame(width: 34, alignment: .trailing)
                }
            }
            .font(.caption2.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(Theme.secondaryText)
            .padding(.bottom, -6)

            VStack(spacing: 14) {
                ForEach(segments.indices, id: \.self) { index in
                    SegmentRow(segment: segments[index], number: number(at: index), maxSpeed: maxSpeed, showsHeartRate: showsHeartRate)
                }
            }
        }
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 20))
    }

    /// "Run 3": position among segments of the same kind.
    private func number(at index: Int) -> Int {
        segments[...index].filter { $0.kind == segments[index].kind }.count
    }
}

private struct SegmentRow: View {
    let segment: RecordedSegment
    let number: Int
    let maxSpeed: Double
    let showsHeartRate: Bool

    private var speedFraction: Double {
        guard maxSpeed > 0 else { return 0 }
        return segment.distanceMeters / max(segment.activeDuration, 1) / maxSpeed
    }

    private var showsNumber: Bool { segment.kind == .run || segment.kind == .walk }

    var body: some View {
        VStack(spacing: 6) {
            HStack(spacing: 10) {
                Image(systemName: segment.kind.symbol)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(segment.kind.color)
                    .frame(width: 22)
                Text(showsNumber ? "\(segment.kind.voicePrompt) \(number)" : segment.kind.voicePrompt)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                Spacer()
                Text(Format.clock(segment.activeDuration))
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 48, alignment: .trailing)
                Text(String(format: "%.2f", segment.distanceMeters / 1000))
                    .font(.footnote.weight(.semibold).monospacedDigit())
                    .foregroundStyle(Theme.secondaryText)
                    .frame(width: 40, alignment: .trailing)
                Text(Format.pace(seconds: segment.activeDuration, meters: segment.distanceMeters))
                    .font(.subheadline.weight(.black).monospacedDigit())
                    .frame(width: 52, alignment: .trailing)
                if showsHeartRate {
                    Text(segment.averageHeartRate.map { "\(Int($0.rounded()))" } ?? "—")
                        .font(.footnote.weight(.semibold).monospacedDigit())
                        .foregroundStyle(Theme.secondaryText)
                        .frame(width: 34, alignment: .trailing)
                }
            }
            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.text.opacity(0.08))
                    Capsule().fill(segment.kind.color)
                        .frame(width: proxy.size.width * speedFraction)
                }
            }
            .frame(height: 4)
            .padding(.leading, 32)
        }
        .accessibilityElement(children: .combine)
    }
}

private struct StatTile: View {
    let value: String
    let unit: String?
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.system(size: 30, weight: .black, design: .rounded).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if let unit {
                    Text(unit)
                        .font(.caption.weight(.bold))
                        .foregroundStyle(Theme.secondaryText)
                }
            }
            Text(label)
                .font(.caption2.weight(.bold))
                .tracking(1)
                .foregroundStyle(Theme.secondaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 18))
    }
}

/// The recorded route, with the camera framed to the area actually covered.
private struct RouteMap: View {
    private let coordinates: [CLLocationCoordinate2D]

    init(points: [RoutePoint]) {
        coordinates = points
            .sorted { $0.timestamp < $1.timestamp }
            .map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
    }

    var body: some View {
        if coordinates.count > 1, let first = coordinates.first, let last = coordinates.last {
            Map(initialPosition: .rect(Self.fittedRect(for: coordinates))) {
                MapPolyline(coordinates: coordinates)
                    .stroke(Theme.accent, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                Annotation("Start", coordinate: first) {
                    Circle().fill(.white).frame(width: 12, height: 12)
                        .overlay(Circle().stroke(.black, lineWidth: 2))
                }
                .annotationTitles(.hidden)
                Annotation("Finish", coordinate: last) {
                    Circle().fill(Theme.accent).frame(width: 14, height: 14)
                        .overlay(Circle().stroke(.black, lineWidth: 2))
                }
                .annotationTitles(.hidden)
            }
            .mapStyle(.standard(elevation: .flat, emphasis: .muted, pointsOfInterest: .excludingAll))
        } else {
            VStack(spacing: 10) {
                Image(systemName: "location.slash")
                    .font(.title.weight(.bold))
                Text("No GPS route was recorded for this run.")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Theme.secondaryText)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.card)
        }
    }

    /// Bounding box of the route with breathing room, and a floor so a short
    /// loop doesn't zoom in to street-furniture level.
    private static func fittedRect(for coordinates: [CLLocationCoordinate2D]) -> MKMapRect {
        let rect = coordinates
            .map { MKMapRect(origin: MKMapPoint($0), size: MKMapSize(width: 0, height: 0)) }
            .reduce(MKMapRect.null) { $0.union($1) }
        let minimumSide = MKMapPointsPerMeterAtLatitude(coordinates[0].latitude) * 400
        let width = max(rect.size.width * 1.35, minimumSide)
        let height = max(rect.size.height * 1.35, minimumSide)
        return MKMapRect(
            x: rect.midX - width / 2,
            y: rect.midY - height / 2,
            width: width,
            height: height
        )
    }
}
