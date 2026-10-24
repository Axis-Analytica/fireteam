#pragma once

#include <QHash>
#include <QJsonObject>
#include <QObject>
#include <QPointer>
#include <QStringList>
#include <QTcpServer>
#include <QTimer>

class Operations;
class QNetworkAccessManager;
class QTcpSocket;

// The field terminal: a small web dashboard for checking on and steering
// operations from a phone. It's off until switched on; then it listens on
// this machine only, or on the local network when asked. Every API call
// needs the pairing token, and planning or deploying new work stays on the
// desktop. Optional ntfy pushes send alerts to a topic the operator owns.
class FieldTerminal : public QObject {
    Q_OBJECT
    Q_PROPERTY(bool enabled READ enabled WRITE setEnabled NOTIFY changed)
    Q_PROPERTY(bool lan READ lan WRITE setLan NOTIFY changed)
    Q_PROPERTY(int port READ port WRITE setPort NOTIFY changed)
    Q_PROPERTY(bool listening READ listening NOTIFY changed)
    Q_PROPERTY(QString error READ error NOTIFY changed)
    Q_PROPERTY(QStringList addresses READ addresses NOTIFY changed)
    Q_PROPERTY(QString pairingUrl READ pairingUrl NOTIFY changed)
    Q_PROPERTY(QString pairingCode READ pairingCode NOTIFY changed)
    Q_PROPERTY(int clients READ clients NOTIFY clientsChanged)
    Q_PROPERTY(QString ntfyUrl READ ntfyUrl WRITE setNtfyUrl NOTIFY changed)

public:
    FieldTerminal(Operations &ops, const QString &dataDirectory, QObject *parent = nullptr);
    ~FieldTerminal() override;

    bool enabled() const { return m_enabled; }
    void setEnabled(bool enabled);
    bool lan() const { return m_lan; }
    void setLan(bool lan);
    int port() const { return m_port; }
    void setPort(int port);
    bool listening() const { return m_server.isListening(); }
    QString error() const { return m_error; }
    QStringList addresses() const;
    QString pairingUrl() const;
    // The pairing address as an SVG QR code (data: URL), when qrencode is
    // installed.
    QString pairingCode() const;
    int clients() const { return m_streams.size(); }
    QString ntfyUrl() const { return m_ntfy; }
    void setNtfyUrl(const QString &url);
    QString token() const { return m_token; }
    quint16 serverPort() const { return m_server.serverPort(); }

    // A new token: every paired device has to pair again.
    Q_INVOKABLE void newToken();
    Q_INVOKABLE void testPush();

    // Sends an alert to ntfy, when a topic is set.
    void push(const QString &title, const QString &body);

signals:
    void changed();
    void clientsChanged();

private:
    struct Request {
        QString method, path;
        QHash<QString, QString> headers, query;
        QByteArray body;
    };
    void listen();
    void accept();
    void read(QTcpSocket *socket);
    void handle(QTcpSocket *socket, const Request &request);
    void reply(QTcpSocket *socket, int status, const QByteArray &type, const QByteArray &body);
    void replyJson(QTcpSocket *socket, int status, const QJsonObject &body);
    bool authorised(const Request &request) const;
    QJsonObject state() const;
    QJsonObject operation(int row) const;
    QJsonObject act(int row, const QString &action, const QJsonObject &body);
    void broadcast();
    void load();
    void save() const;

    Operations &m_ops;
    QString m_path;
    QTcpServer m_server;
    bool m_enabled = false;
    bool m_lan = false;
    int m_port = 7788;
    QString m_token;
    QString m_error;
    QString m_ntfy;
    QHash<QTcpSocket *, QByteArray> m_buffers;
    QList<QPointer<QTcpSocket>> m_streams;
    QTimer m_notice;
    QTimer m_keepalive;
    QNetworkAccessManager *m_network = nullptr;
};
