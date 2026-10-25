// Theme watching follows Omacut (MIT, David Heinemeier Hansson).
#include "theme.h"

#include <QColor>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QStandardPaths>
#include <algorithm>
#include <cmath>

Theme::Theme(const QString &directory, QObject *parent, const QString &hyprctl)
    : QObject(parent),
      m_directory(directory.isEmpty() ? QDir::homePath() + "/.local/state/omarchy/current" : directory) {
    m_debounce.setSingleShot(true);
    m_debounce.setInterval(80);
    connect(&m_watcher, &QFileSystemWatcher::directoryChanged, this, [this] { m_debounce.start(); });
    connect(&m_watcher, &QFileSystemWatcher::fileChanged, this, [this] { m_debounce.start(); });
    connect(&m_debounce, &QTimer::timeout, this, &Theme::reload);

    // Corners follow Hyprland's effective rounding, which themes and personal
    // overrides can both set, so ask hyprctl rather than reading its config.
    // Without Hyprland the corners stay sharp, like Omarchy's default.
    m_hyprctl = !hyprctl.isEmpty() ? hyprctl
              : directory.isEmpty() && !qEnvironmentVariableIsEmpty("HYPRLAND_INSTANCE_SIGNATURE")
                  ? QStandardPaths::findExecutable("hyprctl") : QString();
    m_roundingTimeout.setSingleShot(true);
    m_roundingTimeout.setInterval(500);
    connect(&m_roundingTimeout, &QTimer::timeout, &m_roundingProcess, &QProcess::kill);
    connect(&m_roundingProcess, &QProcess::errorOccurred, this, [this] { m_roundingTimeout.stop(); });
    connect(&m_roundingProcess, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
        m_roundingTimeout.stop();
        const auto value = QJsonDocument::fromJson(m_roundingProcess.readAllStandardOutput()).object().value("int");
        if (code != 0 || status != QProcess::NormalExit || !value.isDouble() || value.toInt(-1) < 0)
            return;
        if (value.toInt() != m_radius) {
            m_radius = value.toInt();
            emit changed();
        }
    });
    m_roundingPoll.setInterval(1000);
    connect(&m_roundingPoll, &QTimer::timeout, this, &Theme::refreshRounding);
    if (!m_hyprctl.isEmpty())
        m_roundingPoll.start();
    reload();
}

Theme::~Theme() {
    if (m_roundingProcess.state() != QProcess::NotRunning) {
        m_roundingProcess.kill();
        m_roundingProcess.waitForFinished(1000);
    }
}

void Theme::refreshRounding() {
    if (m_hyprctl.isEmpty() || m_roundingProcess.state() != QProcess::NotRunning)
        return;
    m_roundingProcess.start(m_hyprctl, {"-j", "getoption", "decoration:rounding"});
    m_roundingTimeout.start();
}

QString Theme::readAccent(const QString &path) {
    QFile file(path);
    if (file.open(QIODevice::ReadOnly)) {
        const QRegularExpression expression(R"re(^\s*accent\s*=\s*["'](#[0-9a-fA-F]{6})["'])re",
                                            QRegularExpression::MultilineOption);
        const auto match = expression.match(QString::fromUtf8(file.readAll()));
        if (match.hasMatch())
            return match.captured(1);
    }
    return "#FFD60A";
}

// Black or white, whichever reads on the accent (WCAG relative luminance).
QString Theme::accentForeground() const {
    const QColor c(m_accent);
    auto linear = [](double v) { return v <= .04045 ? v / 12.92 : std::pow((v + .055) / 1.055, 2.4); };
    const double luminance = .2126 * linear(c.redF()) + .7152 * linear(c.greenF()) + .0722 * linear(c.blueF());
    return luminance > .179 ? "black" : "white";
}

// The accent's hue in OKLCH, and whether it has one at all: a grey or white
// accent tints nothing.
static void accentHue(const QString &accent, double *hue, double *chroma) {
    const QColor c(accent);
    auto linear = [](double v) { return v <= .04045 ? v / 12.92 : std::pow((v + .055) / 1.055, 2.4); };
    const double r = linear(c.redF()), g = linear(c.greenF()), b = linear(c.blueF());
    const double l = std::cbrt(.4122214708 * r + .5363325363 * g + .0514459929 * b);
    const double m = std::cbrt(.2119034982 * r + .6806995451 * g + .1073969566 * b);
    const double s = std::cbrt(.0883024619 * r + .2817188376 * g + .6299787005 * b);
    const double A = 1.9779984951 * l - 2.4285922050 * m + .4505937099 * s;
    const double B = .0259040371 * l + .7827717662 * m - .8086757660 * s;
    *chroma = std::hypot(A, B);
    *hue = std::atan2(B, A) * 180 / M_PI;
}

QString Theme::oklch(double lightness, double chroma, double hue) {
    const double L = lightness / 100, a = chroma * std::cos(hue * M_PI / 180), b = chroma * std::sin(hue * M_PI / 180);
    const double l = std::pow(L + .3963377774 * a + .2158037573 * b, 3);
    const double m = std::pow(L - .1055613458 * a - .0638541728 * b, 3);
    const double s = std::pow(L - .0894841775 * a - 1.2914855480 * b, 3);
    auto gamma = [](double v) {
        v = std::clamp(v, 0.0, 1.0);
        return v <= .0031308 ? 12.92 * v : 1.055 * std::pow(v, 1 / 2.4) - .055;
    };
    return QColor::fromRgbF(gamma(4.0767416621 * l - 3.3077115913 * m + .2309699292 * s),
                            gamma(-1.2684380046 * l + 2.6097574011 * m - .3413193965 * s),
                            gamma(-.0041960863 * l - .7034186147 * m + 1.7076147010 * s)).name();
}

QString Theme::tint(double lightness, double chroma) const {
    double hue = 0, accentChroma = 0;
    accentHue(m_accent, &hue, &accentChroma);
    return oklch(lightness, accentChroma < .03 ? 0 : chroma, hue);
}

// What's added or selected: a dim wash of the accent over the ground.
QString Theme::wash() const {
    double hue = 0, accentChroma = 0;
    accentHue(m_accent, &hue, &accentChroma);
    return oklch(20, std::min(accentChroma * .25, .045), hue);
}

void Theme::reload() {
    refreshRounding();
    const auto paths = m_watcher.files() + m_watcher.directories();
    if (!paths.isEmpty())
        m_watcher.removePaths(paths);

    // A theme switch replaces symlinks and files, so watch the parents too and
    // re-arm after every change. Watching the nearest existing ancestor means
    // installing Omarchy later works without restarting the app.
    QString ancestor = m_directory;
    while (!QFileInfo::exists(ancestor) && ancestor != "/")
        ancestor = QFileInfo(ancestor).absolutePath();
    QStringList candidates{ancestor, QFileInfo(ancestor).absolutePath(), m_directory,
                           m_directory + "/theme", m_directory + "/theme/colors.toml"};
    candidates.removeDuplicates();
    for (const auto &path : candidates)
        if (QFileInfo::exists(path))
            m_watcher.addPath(path);

    const auto accent = readAccent(m_directory + "/theme/colors.toml");
    if (accent != m_accent) {
        m_accent = accent;
        emit changed();
    }
}
