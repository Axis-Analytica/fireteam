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
    // Asks Hyprland to focus Fireteam's window.
    static void focusFireteam();

signals:
    void activated(const QString &opId);

private:
    QString m_notifySend;
};
