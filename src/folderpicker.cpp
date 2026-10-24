#include "folderpicker.h"

#include <QDBusConnection>
#include <QDBusInterface>
#include <QDBusReply>
#include <QRandomGenerator>
#include <QUrl>

void FolderPicker::pick(const QString &title) {
    if (busy())
        return;
    QDBusConnection bus = QDBusConnection::sessionBus();
    const QString token = QString("fireteam%1").arg(QRandomGenerator::global()->generate());

    // Subscribing before the call avoids missing a fast response; the portal
    // derives the request path from our bus name and the handle token.
    const QString sender = bus.baseService().mid(1).replace('.', '_');
    m_handle = QString("/org/freedesktop/portal/desktop/request/%1/%2").arg(sender, token);
    bus.connect("org.freedesktop.portal.Desktop", m_handle, "org.freedesktop.portal.Request", "Response", this,
                SLOT(response(uint, QVariantMap)));
    emit busyChanged();

    QDBusInterface chooser("org.freedesktop.portal.Desktop", "/org/freedesktop/portal/desktop",
                           "org.freedesktop.portal.FileChooser", bus);
    const QVariantMap options{{"handle_token", token}, {"directory", true}, {"modal", true}};
    const QDBusReply<QDBusObjectPath> reply = chooser.call("OpenFile", QString(), title, options);
    if (!reply.isValid()) {
        release();
        emit failed(tr("The desktop file picker isn't available: %1").arg(reply.error().message()));
    } else if (reply.value().path() != m_handle) {
        // Older portals pick their own path; follow it.
        release();
        m_handle = reply.value().path();
        bus.connect("org.freedesktop.portal.Desktop", m_handle, "org.freedesktop.portal.Request", "Response",
                    this, SLOT(response(uint, QVariantMap)));
        emit busyChanged();
    }
}

void FolderPicker::response(uint code, const QVariantMap &results) {
    release();
    const QStringList uris = results.value("uris").toStringList();
    if (code == 0 && !uris.isEmpty())
        emit picked(QUrl(uris.first()).toLocalFile());
}

void FolderPicker::release() {
    if (m_handle.isEmpty())
        return;
    QDBusConnection::sessionBus().disconnect("org.freedesktop.portal.Desktop", m_handle,
                                             "org.freedesktop.portal.Request", "Response", this,
                                             SLOT(response(uint, QVariantMap)));
    m_handle.clear();
    emit busyChanged();
}
