#pragma once

#include <QDBusObjectPath>
#include <QObject>
#include <QVariantMap>

// Asks xdg-desktop-portal for a directory, so the picker is the desktop's own
// rather than a Qt dialog.
class FolderPicker : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY busyChanged)

public:
    explicit FolderPicker(QObject *parent = nullptr) : QObject(parent) {}

    bool busy() const { return !m_handle.isEmpty(); }
    Q_INVOKABLE void pick(const QString &title);

signals:
    void picked(const QString &path);
    void failed(const QString &message);
    void busyChanged();

private slots:
    void response(uint code, const QVariantMap &results);

private:
    void release();
    QString m_handle;
};
