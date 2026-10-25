#pragma once

#include <QObject>
#include <QString>

// Desktop notifications through notify-send, which mako shows on Omarchy.
// Clicking one asks Hyprland to focus Fireteam and reports which operation
// it was about.
class Notifier : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool available READ available CONSTANT)

public:
    explicit Notifier(QObject *parent = nullptr);
    bool available() const { return !m_notifySend.isEmpty(); }

    Q_INVOKABLE void send(const QString &opId, const QString &title, const QString &body);
    // Starts a fresh Fireteam a moment after this one quits (the window then
    // quits), so settings read at start, like the interface size, apply.
    Q_INVOKABLE void relaunch();
    // Asks Hyprland to focus Fireteam's window.
    static void focusFireteam();

signals:
    void activated(const QString &opId);

private:
    QString m_notifySend;
};
