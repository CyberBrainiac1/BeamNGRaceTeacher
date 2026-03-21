#include <algorithm>
#include <cctype>
#include <cmath>
#include <cstdlib>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <map>
#include <sstream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

struct JsonValue {
  enum class Type { Null, Bool, Number, String, Array, Object };

  using Array = std::vector<JsonValue>;
  using Object = std::map<std::string, JsonValue>;

  Type type = Type::Null;
  bool boolValue = false;
  double numberValue = 0.0;
  std::string stringValue;
  Array arrayValue;
  Object objectValue;

  static JsonValue null() { return JsonValue(); }
  static JsonValue boolean(bool value) {
    JsonValue out;
    out.type = Type::Bool;
    out.boolValue = value;
    return out;
  }
  static JsonValue number(double value) {
    JsonValue out;
    out.type = Type::Number;
    out.numberValue = value;
    return out;
  }
  static JsonValue string(std::string value) {
    JsonValue out;
    out.type = Type::String;
    out.stringValue = std::move(value);
    return out;
  }
  static JsonValue array() {
    JsonValue out;
    out.type = Type::Array;
    return out;
  }
  static JsonValue object() {
    JsonValue out;
    out.type = Type::Object;
    return out;
  }

  bool isNull() const { return type == Type::Null; }
  bool isBool() const { return type == Type::Bool; }
  bool isNumber() const { return type == Type::Number; }
  bool isString() const { return type == Type::String; }
  bool isArray() const { return type == Type::Array; }
  bool isObject() const { return type == Type::Object; }

  const JsonValue &at(const std::string &key) const {
    static const JsonValue kNull = JsonValue::null();
    if (!isObject()) {
      return kNull;
    }
    auto it = objectValue.find(key);
    return it == objectValue.end() ? kNull : it->second;
  }
};

class JsonParser {
 public:
  explicit JsonParser(std::string text) : text_(std::move(text)) {}

  JsonValue parse() {
    skipWhitespace();
    JsonValue value = parseValue();
    skipWhitespace();
    if (pos_ != text_.size()) {
      throw std::runtime_error("Unexpected trailing JSON data");
    }
    return value;
  }

 private:
  JsonValue parseValue() {
    skipWhitespace();
    if (pos_ >= text_.size()) {
      throw std::runtime_error("Unexpected end of JSON input");
    }

    const char c = text_[pos_];
    if (c == '{') return parseObject();
    if (c == '[') return parseArray();
    if (c == '"') return JsonValue::string(parseString());
    if (c == 't') return parseTrue();
    if (c == 'f') return parseFalse();
    if (c == 'n') return parseNull();
    if (c == '-' || std::isdigit(static_cast<unsigned char>(c))) return parseNumber();

    throw std::runtime_error("Invalid JSON token");
  }

  JsonValue parseObject() {
    expect('{');
    JsonValue out = JsonValue::object();
    skipWhitespace();
    if (peek('}')) {
      expect('}');
      return out;
    }

    while (true) {
      skipWhitespace();
      if (!peek('"')) {
        throw std::runtime_error("Expected string key in JSON object");
      }
      const std::string key = parseString();
      skipWhitespace();
      expect(':');
      out.objectValue[key] = parseValue();
      skipWhitespace();
      if (peek('}')) {
        expect('}');
        break;
      }
      expect(',');
    }

    return out;
  }

  JsonValue parseArray() {
    expect('[');
    JsonValue out = JsonValue::array();
    skipWhitespace();
    if (peek(']')) {
      expect(']');
      return out;
    }

    while (true) {
      out.arrayValue.push_back(parseValue());
      skipWhitespace();
      if (peek(']')) {
        expect(']');
        break;
      }
      expect(',');
    }

    return out;
  }

  std::string parseString() {
    expect('"');
    std::string out;

    while (pos_ < text_.size()) {
      char c = text_[pos_++];
      if (c == '"') {
        return out;
      }
      if (c == '\\') {
        if (pos_ >= text_.size()) {
          throw std::runtime_error("Invalid JSON escape");
        }
        char esc = text_[pos_++];
        switch (esc) {
          case '"': out.push_back('"'); break;
          case '\\': out.push_back('\\'); break;
          case '/': out.push_back('/'); break;
          case 'b': out.push_back('\b'); break;
          case 'f': out.push_back('\f'); break;
          case 'n': out.push_back('\n'); break;
          case 'r': out.push_back('\r'); break;
          case 't': out.push_back('\t'); break;
          case 'u':
            throw std::runtime_error("Unicode escapes are not supported in this parser");
          default:
            throw std::runtime_error("Unsupported JSON escape");
        }
      } else {
        out.push_back(c);
      }
    }

    throw std::runtime_error("Unterminated JSON string");
  }

  JsonValue parseTrue() {
    expectLiteral("true");
    return JsonValue::boolean(true);
  }

  JsonValue parseFalse() {
    expectLiteral("false");
    return JsonValue::boolean(false);
  }

  JsonValue parseNull() {
    expectLiteral("null");
    return JsonValue::null();
  }

  JsonValue parseNumber() {
    const char *start = text_.c_str() + pos_;
    char *end = nullptr;
    double value = std::strtod(start, &end);
    if (end == start) {
      throw std::runtime_error("Invalid JSON number");
    }
    pos_ += static_cast<std::size_t>(end - start);
    return JsonValue::number(value);
  }

  bool peek(char expected) const {
    return pos_ < text_.size() && text_[pos_] == expected;
  }

  void expect(char expected) {
    if (pos_ >= text_.size() || text_[pos_] != expected) {
      throw std::runtime_error("Unexpected JSON character");
    }
    ++pos_;
  }

  void expectLiteral(const char *literal) {
    while (*literal != '\0') {
      if (pos_ >= text_.size() || text_[pos_] != *literal) {
        throw std::runtime_error("Unexpected JSON literal");
      }
      ++pos_;
      ++literal;
    }
  }

  void skipWhitespace() {
    while (pos_ < text_.size() && std::isspace(static_cast<unsigned char>(text_[pos_]))) {
      ++pos_;
    }
  }

  std::string text_;
  std::size_t pos_ = 0;
};

static std::string escapeJsonString(const std::string &input) {
  std::ostringstream out;
  for (char c : input) {
    switch (c) {
      case '"': out << "\\\""; break;
      case '\\': out << "\\\\"; break;
      case '\b': out << "\\b"; break;
      case '\f': out << "\\f"; break;
      case '\n': out << "\\n"; break;
      case '\r': out << "\\r"; break;
      case '\t': out << "\\t"; break;
      default:
        if (static_cast<unsigned char>(c) < 0x20) {
          out << "\\u" << std::hex << std::setw(4) << std::setfill('0')
              << static_cast<int>(static_cast<unsigned char>(c))
              << std::dec << std::setfill(' ');
        } else {
          out << c;
        }
    }
  }
  return out.str();
}

static void writeJson(const JsonValue &value, std::ostream &out) {
  switch (value.type) {
    case JsonValue::Type::Null:
      out << "null";
      break;
    case JsonValue::Type::Bool:
      out << (value.boolValue ? "true" : "false");
      break;
    case JsonValue::Type::Number:
      out << std::setprecision(12) << value.numberValue;
      break;
    case JsonValue::Type::String:
      out << '"' << escapeJsonString(value.stringValue) << '"';
      break;
    case JsonValue::Type::Array: {
      out << "[";
      for (std::size_t i = 0; i < value.arrayValue.size(); ++i) {
        if (i > 0) out << ",";
        writeJson(value.arrayValue[i], out);
      }
      out << "]";
      break;
    }
    case JsonValue::Type::Object: {
      out << "{";
      bool first = true;
      for (const auto &entry : value.objectValue) {
        if (!first) out << ",";
        first = false;
        out << '"' << escapeJsonString(entry.first) << "\":";
        writeJson(entry.second, out);
      }
      out << "}";
      break;
    }
  }
}

static std::string readFile(const std::string &path) {
  std::ifstream in(path, std::ios::binary);
  if (!in) {
    throw std::runtime_error("Failed to open input file: " + path);
  }
  std::ostringstream buffer;
  buffer << in.rdbuf();
  return buffer.str();
}

static void writeFile(const std::string &path, const JsonValue &value) {
  std::ofstream out(path, std::ios::binary | std::ios::trunc);
  if (!out) {
    throw std::runtime_error("Failed to open output file: " + path);
  }
  writeJson(value, out);
  out << "\n";
}

static double getNumber(const JsonValue &object, const std::string &key, double fallback) {
  const JsonValue &value = object.at(key);
  return value.isNumber() ? value.numberValue : fallback;
}

static bool getBool(const JsonValue &object, const std::string &key, bool fallback) {
  const JsonValue &value = object.at(key);
  return value.isBool() ? value.boolValue : fallback;
}

struct Vec3 {
  double x = 0.0;
  double y = 0.0;
  double z = 0.0;
};

static Vec3 operator+(const Vec3 &a, const Vec3 &b) { return {a.x + b.x, a.y + b.y, a.z + b.z}; }
static Vec3 operator-(const Vec3 &a, const Vec3 &b) { return {a.x - b.x, a.y - b.y, a.z - b.z}; }
static Vec3 operator*(const Vec3 &v, double s) { return {v.x * s, v.y * s, v.z * s}; }
static Vec3 operator/(const Vec3 &v, double s) { return {v.x / s, v.y / s, v.z / s}; }

static double dot(const Vec3 &a, const Vec3 &b) { return a.x * b.x + a.y * b.y + a.z * b.z; }
static Vec3 cross(const Vec3 &a, const Vec3 &b) {
  return {
      a.y * b.z - a.z * b.y,
      a.z * b.x - a.x * b.z,
      a.x * b.y - a.y * b.x};
}
static double lengthSquared(const Vec3 &v) { return dot(v, v); }
static double length(const Vec3 &v) { return std::sqrt(lengthSquared(v)); }
static double squaredDistance(const Vec3 &a, const Vec3 &b) { return lengthSquared(a - b); }

static Vec3 normalizeSafe(const Vec3 &v, const Vec3 &fallback) {
  double len = length(v);
  if (len < 1e-6) {
    return fallback;
  }
  return v / len;
}

static double clampDouble(double value, double low, double high) {
  return std::max(low, std::min(high, value));
}

static double lerp(double a, double b, double t) {
  return a + (b - a) * t;
}

struct PathPoint {
  Vec3 pos;
  double widthLeft = 6.0;
  double widthRight = 6.0;
  double s = 0.0;
  double curvature = 0.0;
  Vec3 tangent{1.0, 0.0, 0.0};
  Vec3 normal{0.0, 1.0, 0.0};
  double preferredOffset = 0.0;
  double lateralOffset = 0.0;
};

struct Segment {
  std::size_t a = 0;
  std::size_t b = 0;
  double start = 0.0;
  double len = 0.0;
};

struct SolverConfig {
  bool closed = false;
  int iterations = 24;
  double alpha = 0.18;
  double wContouring = 0.85;
  double wLag = 0.75;
  double wProgress = 0.55;
  double wSmooth = 0.60;
  double wCurvature = 1.0;
  double wPreferred = 1.35;
  int lookaheadPts = 10;
  double maxTrackUsage = 0.92;
  double preferredScale = 1.0;
  int endpointRampCount = 8;
};

struct VehicleConfig {
  double mu = 1.12;
  double maxAccel = 4.5;
  double maxBrake = 8.5;
  double vmax = 83.0;
};

struct PlanOutput {
  bool closed = false;
  double totalLength = 0.0;
  std::vector<PathPoint> points;
  std::vector<double> speedProfile;
  std::vector<std::string> zones;
};

static int prevIndex(const std::vector<PathPoint> &path, bool closed, int i) {
  if (i > 0) {
    return i - 1;
  }
  if (closed && path.size() > 2) {
    return static_cast<int>(path.size()) - 1;
  }
  return -1;
}

static int nextIndex(const std::vector<PathPoint> &path, bool closed, int i) {
  if (i + 1 < static_cast<int>(path.size())) {
    return i + 1;
  }
  if (closed && path.size() > 2) {
    return 0;
  }
  return -1;
}

static void computeGeometry(std::vector<PathPoint> &path, bool closed, double &totalLength) {
  totalLength = 0.0;
  if (path.empty()) {
    return;
  }

  path[0].s = 0.0;
  for (std::size_t i = 1; i < path.size(); ++i) {
    totalLength += length(path[i].pos - path[i - 1].pos);
    path[i].s = totalLength;
  }

  if (closed && path.size() > 2) {
    totalLength += length(path.front().pos - path.back().pos);
  }

  for (int i = 0; i < static_cast<int>(path.size()); ++i) {
    int im1 = prevIndex(path, closed, i);
    int ip1 = nextIndex(path, closed, i);
    Vec3 tangent;
    if (im1 >= 0 && ip1 >= 0) {
      tangent = path[ip1].pos - path[im1].pos;
    } else if (ip1 >= 0) {
      tangent = path[ip1].pos - path[i].pos;
    } else if (im1 >= 0) {
      tangent = path[i].pos - path[im1].pos;
    } else {
      tangent = {1.0, 0.0, 0.0};
    }

    path[i].tangent = normalizeSafe(tangent, {1.0, 0.0, 0.0});
    path[i].normal = normalizeSafe(cross({0.0, 0.0, 1.0}, path[i].tangent), {0.0, 1.0, 0.0});
  }

  for (int i = 0; i < static_cast<int>(path.size()); ++i) {
    int im1 = prevIndex(path, closed, i);
    int ip1 = nextIndex(path, closed, i);
    if (im1 < 0 || ip1 < 0) {
      path[i].curvature = 0.0;
      continue;
    }

    Vec3 a = path[i].pos - path[im1].pos;
    Vec3 b = path[ip1].pos - path[i].pos;
    double lenA = length(a);
    double lenB = length(b);
    if (lenA < 1e-6 || lenB < 1e-6) {
      path[i].curvature = 0.0;
      continue;
    }

    a = a / lenA;
    b = b / lenB;
    double ds = std::max((lenA + lenB) * 0.5, 1e-3);
    double curvature = length(b - a) / ds;
    double crossZ = cross(a, b).z;
    path[i].curvature = curvature * (crossZ >= 0.0 ? 1.0 : -1.0);
  }
}

static std::vector<PathPoint> prepareControlPoints(const JsonValue::Array &input, bool closed) {
  std::vector<PathPoint> control;
  control.reserve(input.size());

  for (const JsonValue &value : input) {
    if (!value.isObject()) {
      continue;
    }
    PathPoint point;
    point.pos = {
        getNumber(value, "x", 0.0),
        getNumber(value, "y", 0.0),
        getNumber(value, "z", 0.0)};
    point.widthLeft = getNumber(value, "widthLeft", getNumber(value, "width", getNumber(value, "radius", 6.0)));
    point.widthRight = getNumber(value, "widthRight", getNumber(value, "width", getNumber(value, "radius", 6.0)));
    control.push_back(point);
  }

  if (closed && control.size() > 2 && squaredDistance(control.front().pos, control.back().pos) < 0.25) {
    control.pop_back();
  }

  return control;
}

static std::vector<Segment> buildSegments(const std::vector<PathPoint> &points, bool closed, double &totalLength) {
  std::vector<Segment> segments;
  totalLength = 0.0;
  if (points.size() < 2) {
    return segments;
  }

  for (std::size_t i = 0; i + 1 < points.size(); ++i) {
    double len = length(points[i + 1].pos - points[i].pos);
    if (len > 1e-3) {
      segments.push_back({i, i + 1, totalLength, len});
      totalLength += len;
    }
  }

  if (closed && points.size() > 2) {
    double len = length(points.front().pos - points.back().pos);
    if (len > 1e-3) {
      segments.push_back({points.size() - 1, 0, totalLength, len});
      totalLength += len;
    }
  }

  return segments;
}

static std::vector<PathPoint> sampleControlPoints(const std::vector<PathPoint> &control,
                                                  const std::vector<Segment> &segments,
                                                  double totalLength,
                                                  double spacing,
                                                  bool closed) {
  if (spacing <= 0.0 || totalLength <= spacing * 0.5 || segments.empty()) {
    return control;
  }

  std::vector<PathPoint> out;
  std::size_t segIdx = 0;

  auto addSample = [&](double targetDist) {
    while (segIdx + 1 < segments.size() && targetDist > segments[segIdx].start + segments[segIdx].len) {
      ++segIdx;
    }

    const Segment &seg = segments[std::min(segIdx, segments.size() - 1)];
    const PathPoint &a = control[seg.a];
    const PathPoint &b = control[seg.b];
    double localDist = clampDouble(targetDist - seg.start, 0.0, seg.len);
    double t = seg.len > 1e-6 ? (localDist / seg.len) : 0.0;

    PathPoint sample;
    sample.pos = a.pos + (b.pos - a.pos) * t;
    sample.widthLeft = lerp(a.widthLeft, b.widthLeft, t);
    sample.widthRight = lerp(a.widthRight, b.widthRight, t);
    out.push_back(sample);
  };

  for (double dist = 0.0; dist < totalLength; dist += spacing) {
    addSample(dist);
  }

  if (!closed) {
    if (out.empty() || squaredDistance(out.back().pos, control.back().pos) > 0.25) {
      out.push_back(control.back());
    }
  }

  return out;
}

static std::vector<PathPoint> buildBaselinePath(const JsonValue::Array &inputPoints,
                                                bool closed,
                                                double resampleSpacing,
                                                double &totalLength) {
  std::vector<PathPoint> control = prepareControlPoints(inputPoints, closed);
  if (control.size() < 2) {
    totalLength = 0.0;
    return {};
  }

  double segmentTotal = 0.0;
  std::vector<Segment> segments = buildSegments(control, closed, segmentTotal);
  std::vector<PathPoint> sampled = sampleControlPoints(control, segments, segmentTotal, resampleSpacing, closed);
  computeGeometry(sampled, closed, totalLength);
  return sampled;
}

static double segmentSpacing(const std::vector<PathPoint> &path, bool closed, int i) {
  int im1 = prevIndex(path, closed, i);
  int ip1 = nextIndex(path, closed, i);
  if (im1 >= 0 && ip1 >= 0) {
    double prevDs = length(path[i].pos - path[im1].pos);
    double nextDs = length(path[ip1].pos - path[i].pos);
    return std::max((prevDs + nextDs) * 0.5, 0.5);
  }
  if (ip1 >= 0) {
    return std::max(length(path[ip1].pos - path[i].pos), 0.5);
  }
  if (im1 >= 0) {
    return std::max(length(path[i].pos - path[im1].pos), 0.5);
  }
  return 1.0;
}

static double endpointBlend(int i, int n, int rampCount) {
  if (rampCount <= 0 || n <= 2) {
    return 1.0;
  }
  double fromStart = clampDouble(static_cast<double>(i) / static_cast<double>(rampCount), 0.0, 1.0);
  double fromEnd = clampDouble(static_cast<double>((n - 1) - i) / static_cast<double>(rampCount), 0.0, 1.0);
  return std::min(fromStart, fromEnd);
}

static void buildCornerPreference(std::vector<PathPoint> &path, const SolverConfig &config) {
  int n = static_cast<int>(path.size());
  for (int i = 0; i < n; ++i) {
    double k0 = path[i].curvature;
    double kAbs = std::abs(k0);

    double futureMax = 0.0;
    double futureSign = 0.0;
    for (int j = 1; j <= config.lookaheadPts; ++j) {
      int idx = i + j;
      if (idx >= n) {
        if (config.closed) {
          idx = idx % n;
        } else {
          break;
        }
      }

      double kj = path[idx].curvature;
      if (std::abs(kj) > futureMax) {
        futureMax = std::abs(kj);
        futureSign = kj >= 0.0 ? 1.0 : -1.0;
      }
    }

    double turnSign = kAbs > 1e-4 ? (k0 >= 0.0 ? 1.0 : -1.0) : futureSign;
    double severity = clampDouble(futureMax * 10.0, 0.0, 1.0);
    double maxOffset = std::min(path[i].widthLeft, path[i].widthRight) * config.maxTrackUsage;
    double trend = futureMax - kAbs;

    double preference = 0.0;
    if (trend > 0.002) {
      preference = -turnSign * maxOffset * 0.8 * severity;
    } else if (trend < -0.002) {
      preference = -turnSign * maxOffset * 0.5 * severity;
    } else {
      preference = turnSign * maxOffset * 0.6 * severity;
    }

    path[i].preferredOffset = preference * config.preferredScale;
  }
}

static std::vector<double> seedOffsets(const std::vector<PathPoint> &path, double maxTrackUsage) {
  std::vector<double> offsets(path.size(), 0.0);
  for (std::size_t i = 0; i < path.size(); ++i) {
    double widthLimit = std::min(path[i].widthLeft, path[i].widthRight) * maxTrackUsage;
    offsets[i] = clampDouble(path[i].preferredOffset, -widthLimit, widthLimit);
  }
  return offsets;
}

static std::vector<PathPoint> buildOffsetPath(const std::vector<PathPoint> &referencePath,
                                              const std::vector<double> &offsets,
                                              bool closed,
                                              double &totalLength) {
  std::vector<PathPoint> out = referencePath;
  for (std::size_t i = 0; i < out.size(); ++i) {
    double offset = i < offsets.size() ? offsets[i] : 0.0;
    out[i].lateralOffset = offset;
    out[i].pos = out[i].pos + out[i].normal * offset;
  }
  computeGeometry(out, closed, totalLength);
  return out;
}

static double solveLocalMpccOffset(const std::vector<PathPoint> &referencePath,
                                   const std::vector<PathPoint> &workingPath,
                                   const std::vector<double> &offsets,
                                   const SolverConfig &config,
                                   int i) {
  int n = static_cast<int>(referencePath.size());
  if (!config.closed && (i == 0 || i == n - 1)) {
    return 0.0;
  }

  int im1 = i > 0 ? i - 1 : n - 1;
  int ip1 = i + 1 < n ? i + 1 : 0;

  double om = offsets[im1];
  double oi = offsets[i];
  double op = offsets[ip1];
  double ds = segmentSpacing(workingPath, config.closed, i);
  double curvature = workingPath[i].curvature;
  double widthLimit = std::min(referencePath[i].widthLeft, referencePath[i].widthRight) * config.maxTrackUsage;
  double pref = referencePath[i].preferredOffset;
  double blend = config.closed ? 1.0 : endpointBlend(i, n, config.endpointRampCount);

  double qContour = config.wContouring * blend;
  double qLag = config.wLag;
  double qProgress = config.wProgress * blend;
  double qSmooth = config.wSmooth;
  double qCurvature = config.wCurvature;
  double qPreferred = config.wPreferred * blend;

  double qRef = qContour + qPreferred;
  double curvatureSq = curvature * curvature;
  double numerator = 2.0 * qRef * pref
      + (2.0 * qSmooth + 4.0 * qCurvature) * (om + op)
      + qProgress * ds * curvature;
  double denominator = 2.0 * qRef
      + 2.0 * qLag * curvatureSq
      + 4.0 * qSmooth
      + 8.0 * qCurvature;

  double target = denominator > 1e-6 ? (numerator / denominator) : oi;
  target = clampDouble(target, -widthLimit, widthLimit);
  return lerp(oi, target, config.alpha);
}

static std::vector<PathPoint> improvePathMPCCStyle(const std::vector<PathPoint> &baselinePath,
                                                   const SolverConfig &config,
                                                   double &totalLength) {
  std::vector<PathPoint> referencePath = baselinePath;
  computeGeometry(referencePath, config.closed, totalLength);
  buildCornerPreference(referencePath, config);

  std::vector<double> offsets = seedOffsets(referencePath, config.maxTrackUsage);
  std::vector<PathPoint> workingPath = buildOffsetPath(referencePath, offsets, config.closed, totalLength);

  for (int iteration = 0; iteration < config.iterations; ++iteration) {
    workingPath = buildOffsetPath(referencePath, offsets, config.closed, totalLength);
    for (int i = 0; i < static_cast<int>(referencePath.size()); ++i) {
      offsets[i] = solveLocalMpccOffset(referencePath, workingPath, offsets, config, i);
    }
  }

  return buildOffsetPath(referencePath, offsets, config.closed, totalLength);
}

static std::string classifyZone(double curvatureAbs, double dv) {
  if (curvatureAbs < 0.01) {
    return dv > 0.5 ? "accel" : "straight";
  }
  if (dv < -1.2) return "brake";
  if (curvatureAbs > 0.065) return "apex";
  if (dv < -0.3) return "turn_in";
  if (dv > 0.2) return "exit";
  return "corner";
}

static void buildSpeedAndZones(const std::vector<PathPoint> &path,
                               bool closed,
                               const VehicleConfig &vehicle,
                               std::vector<double> &speedProfile,
                               std::vector<std::string> &zones) {
  constexpr double g = 9.81;
  int n = static_cast<int>(path.size());
  speedProfile.assign(n, 0.0);
  std::vector<double> ds(n, 0.5);
  zones.assign(n, "straight");

  if (n == 0) {
    return;
  }

  for (int i = 0; i < n; ++i) {
    int prev = i > 0 ? i - 1 : (closed && n > 1 ? n - 1 : std::min(1, n - 1));
    ds[i] = std::max(length(path[i].pos - path[prev].pos), 0.5);
    double curvature = std::max(std::abs(path[i].curvature), 1e-4);
    double vLat = std::sqrt((vehicle.mu * g) / curvature);
    speedProfile[i] = std::min(vLat, vehicle.vmax);
  }

  int smoothingPasses = closed ? 2 : 1;
  for (int pass = 0; pass < smoothingPasses; ++pass) {
    for (int i = 1; i < n; ++i) {
      speedProfile[i] = std::min(speedProfile[i],
                                 std::sqrt(speedProfile[i - 1] * speedProfile[i - 1] + 2.0 * vehicle.maxAccel * ds[i]));
    }
    for (int i = n - 2; i >= 0; --i) {
      speedProfile[i] = std::min(speedProfile[i],
                                 std::sqrt(speedProfile[i + 1] * speedProfile[i + 1] + 2.0 * vehicle.maxBrake * ds[i + 1]));
    }
  }

  for (int i = 0; i < n; ++i) {
    int next = i + 1 < n ? i + 1 : (closed ? 0 : i);
    double dv = speedProfile[next] - speedProfile[i];
    zones[i] = classifyZone(std::abs(path[i].curvature), dv);
  }

  if (!closed && !zones.empty()) {
    zones.back() = "exit";
  }
}

static SolverConfig parseSolverConfig(const JsonValue &value, bool closed) {
  SolverConfig config;
  config.closed = closed;
  config.iterations = static_cast<int>(getNumber(value, "iterations", 24.0));
  config.alpha = getNumber(value, "alpha", 0.18);
  config.wContouring = getNumber(value, "wContouring", 0.85);
  config.wLag = getNumber(value, "wLag", 0.75);
  config.wProgress = getNumber(value, "wProgress", 0.55);
  config.wSmooth = getNumber(value, "wSmooth", 0.60);
  config.wCurvature = getNumber(value, "wCurvature", 1.0);
  config.wPreferred = getNumber(value, "wPreferred", 1.35);
  config.lookaheadPts = static_cast<int>(getNumber(value, "lookaheadPts", 10.0));
  config.maxTrackUsage = getNumber(value, "maxTrackUsage", closed ? 0.92 : 0.40);
  config.preferredScale = getNumber(value, "preferredScale", 1.0);
  config.endpointRampCount = static_cast<int>(getNumber(value, "endpointRampCount", 8.0));
  return config;
}

static VehicleConfig parseVehicleConfig(const JsonValue &value) {
  VehicleConfig config;
  config.mu = getNumber(value, "mu", 1.12);
  config.maxAccel = getNumber(value, "maxAccel", 4.5);
  config.maxBrake = getNumber(value, "maxBrake", 8.5);
  config.vmax = getNumber(value, "vmax", 83.0);
  return config;
}

static JsonValue buildPlanJson(const PlanOutput &plan) {
  JsonValue root = JsonValue::object();
  root.objectValue["ok"] = JsonValue::boolean(true);
  root.objectValue["closed"] = JsonValue::boolean(plan.closed);
  root.objectValue["totalLength"] = JsonValue::number(plan.totalLength);

  JsonValue points = JsonValue::array();
  for (const PathPoint &point : plan.points) {
    JsonValue item = JsonValue::object();
    item.objectValue["x"] = JsonValue::number(point.pos.x);
    item.objectValue["y"] = JsonValue::number(point.pos.y);
    item.objectValue["z"] = JsonValue::number(point.pos.z);
    item.objectValue["widthLeft"] = JsonValue::number(point.widthLeft);
    item.objectValue["widthRight"] = JsonValue::number(point.widthRight);
    item.objectValue["preferredOffset"] = JsonValue::number(point.preferredOffset);
    item.objectValue["lateralOffset"] = JsonValue::number(point.lateralOffset);
    points.arrayValue.push_back(std::move(item));
  }
  root.objectValue["points"] = std::move(points);

  JsonValue speedProfile = JsonValue::array();
  for (double speed : plan.speedProfile) {
    speedProfile.arrayValue.push_back(JsonValue::number(speed));
  }
  root.objectValue["speedProfile"] = std::move(speedProfile);

  JsonValue zones = JsonValue::array();
  for (const std::string &zone : plan.zones) {
    zones.arrayValue.push_back(JsonValue::string(zone));
  }
  root.objectValue["zones"] = std::move(zones);

  JsonValue meta = JsonValue::object();
  meta.objectValue["pointCount"] = JsonValue::number(static_cast<double>(plan.points.size()));
  meta.objectValue["plannerMode"] = JsonValue::string("native");
  root.objectValue["meta"] = std::move(meta);

  return root;
}

static JsonValue buildErrorJson(const std::string &message) {
  JsonValue root = JsonValue::object();
  root.objectValue["ok"] = JsonValue::boolean(false);
  root.objectValue["error"] = JsonValue::string(message);
  return root;
}

static JsonValue handleRequest(const JsonValue &request) {
  if (!request.isObject()) {
    throw std::runtime_error("Request root must be a JSON object");
  }

  const JsonValue &pointsValue = request.at("points");
  if (!pointsValue.isArray() || pointsValue.arrayValue.size() < 2) {
    throw std::runtime_error("Request must contain at least two points");
  }

  const JsonValue &pathOptions = request.at("pathOptions");
  const JsonValue &mpcc = request.at("mpcc");
  const JsonValue &vehicle = request.at("vehicle");

  bool closed = getBool(request, "closed", getBool(pathOptions, "closed", false));
  double resampleSpacing = getNumber(pathOptions, "resampleSpacing", 0.0);

  double baselineLength = 0.0;
  std::vector<PathPoint> baseline = buildBaselinePath(pointsValue.arrayValue, closed, resampleSpacing, baselineLength);
  if (baseline.size() < 4) {
    throw std::runtime_error("Baseline path is too short");
  }

  SolverConfig solverConfig = parseSolverConfig(mpcc, closed);
  VehicleConfig vehicleConfig = parseVehicleConfig(vehicle);

  PlanOutput plan;
  plan.closed = closed;
  plan.points = improvePathMPCCStyle(baseline, solverConfig, plan.totalLength);
  buildSpeedAndZones(plan.points, closed, vehicleConfig, plan.speedProfile, plan.zones);
  return buildPlanJson(plan);
}

int main(int argc, char **argv) {
  if (argc < 3) {
    std::cerr << "Usage: beamng_racecoach_native <request.json> <response.json>\n";
    return 1;
  }

  const std::string requestPath = argv[1];
  const std::string responsePath = argv[2];

  try {
    JsonParser parser(readFile(requestPath));
    JsonValue request = parser.parse();
    JsonValue response = handleRequest(request);
    writeFile(responsePath, response);
    return 0;
  } catch (const std::exception &e) {
    try {
      writeFile(responsePath, buildErrorJson(e.what()));
    } catch (...) {
    }
    std::cerr << e.what() << "\n";
    return 1;
  }
}
