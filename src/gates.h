#pragma once

#include <QObject>
#include <QPointer>
#include <QProcess>
#include <QVariantList>

// Gates: the project's own checks (build, test, lint) that Fireteam runs
// itself after each cycle, rather than taking the agent's word for them.
class Gates : public QObject {
    Q_OBJECT

public:
    explicit Gates(QObject *parent = nullptr);
    ~Gates() override;

    // The checks a project declares, from package.json scripts, a Makefile,
    // Cargo.toml, go.mod, Python test setups, or bin/test: [{name, command}].
    static QVariantList detect(const QString &directory);

    // Runs each gate in turn with sh -c, each cut off after timeoutSeconds.
    // finished() carries [{name, command, passed, seconds, output}], the
    // output being the end of what it printed.
    void run(const QString &directory, const QVariantList &gates, int timeoutSeconds = 600);
    void stop();
    bool running() const { return m_process != nullptr || m_server != nullptr; }

    // Visual proof: starts the project's preview command (if any), waits for
    // url to answer, and screenshots it with headless Chromium into path.
    // previewed() carries the path, or empty with what went wrong.
    void preview(const QString &directory, const QString &command, const QString &url, const QString &path);
    static QString browser();

signals:
    void started(const QString &name);
    void finished(const QVariantList &results);
    void previewed(const QString &path, const QString &problem);

private:
    void next();

    QString m_directory;
    QVariantList m_queue;
    QVariantList m_results;
    void stopServer();
    void shoot(const QString &url, const QString &path);

    QPointer<QProcess> m_process;
    QPointer<QProcess> m_server;
    int m_timeout = 600;
};
