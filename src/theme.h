#pragma once

#include <QFileSystemWatcher>
#include <QObject>
#include <QProcess>
#include <QTimer>

class Theme : public QObject {
    Q_OBJECT
    Q_PROPERTY(QString accent READ accent NOTIFY changed)
    Q_PROPERTY(QString accentForeground READ accentForeground NOTIFY changed)
    Q_PROPERTY(int radius READ radius NOTIFY changed)
    // The ground and ink, tinted toward the accent's hue: one hue in a ramp of
    // lightness, as Hallmark's Terminal theme lays it out.
    Q_PROPERTY(QString paper READ paper NOTIFY changed)
    Q_PROPERTY(QString paper2 READ paper2 NOTIFY changed)
    Q_PROPERTY(QString paper3 READ paper3 NOTIFY changed)
    Q_PROPERTY(QString ink READ ink NOTIFY changed)
    Q_PROPERTY(QString ink2 READ ink2 NOTIFY changed)
    Q_PROPERTY(QString muted READ muted NOTIFY changed)
    Q_PROPERTY(QString faint READ faint NOTIFY changed)
    Q_PROPERTY(QString rule READ rule NOTIFY changed)
    Q_PROPERTY(QString rule2 READ rule2 NOTIFY changed)
    Q_PROPERTY(QString wash READ wash NOTIFY changed)

public:
    explicit Theme(const QString &currentDirectory = {}, QObject *parent = nullptr, const QString &hyprctl = {});
    ~Theme() override;

    QString accent() const { return m_accent; }
    QString accentForeground() const;
    int radius() const { return m_radius; }
    QString paper() const { return tint(12.5, 0.008); }
    QString paper2() const { return tint(15.5, 0.01); }
    QString paper3() const { return tint(19.5, 0.012); }
    QString ink() const { return tint(94, 0.012); }
    QString ink2() const { return tint(82, 0.016); }
    QString muted() const { return tint(64, 0.02); }
    QString faint() const { return tint(46, 0.02); }
    QString rule() const { return tint(26, 0.012); }
    QString rule2() const { return tint(36, 0.016); }
    QString wash() const;

    // A colour in OKLCH (lightness in percent), at the accent's hue.
    QString tint(double lightness, double chroma) const;
    static QString oklch(double lightness, double chroma, double hue);

    static QString readAccent(const QString &path);

signals:
    void changed();

private:
    void reload();
    void refreshRounding();

    QString m_directory;
    QString m_accent = "#FFD60A";
    QFileSystemWatcher m_watcher;
    QTimer m_debounce;
    QString m_hyprctl;
    int m_radius = 0;
    QProcess m_roundingProcess;
    QTimer m_roundingPoll, m_roundingTimeout;
};
