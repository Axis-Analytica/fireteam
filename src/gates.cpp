#include "gates.h"

#include <QDir>
#include <QElapsedTimer>
#include <QFile>
#include <QFileInfo>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QTimer>
#include <QStandardPaths>
#include <QTcpSocket>
#include <QUrl>
#include <csignal>
#include <memory>
#include <unistd.h>

// How much of a gate's output is kept: the end, where the failure usually is.
static constexpr int OutputTail = 4000;

Gates::Gates(QObject *parent) : QObject(parent) {}

Gates::~Gates() {
    stop();
    stopServer();
}

QString Gates::browser() {
    for (const char *name : {"chromium", "chromium-browser", "google-chrome-stable", "google-chrome", "brave"})
        if (const QString path = QStandardPaths::findExecutable(name); !path.isEmpty())
            return path;
    return {};
}

void Gates::preview(const QString &directory, const QString &command, const QString &url, const QString &path) {
    if (browser().isEmpty()) {
        emit previewed({}, tr("No Chromium-based browser is installed for screenshots."));
        return;
    }
    const QUrl target(url);
    if (!target.isValid() || target.host().isEmpty()) {
        emit previewed({}, tr("The preview address isn't a URL."));
        return;
    }
    if (!command.trimmed().isEmpty()) {
        // In a process group of its own, so the dev server and whatever it
        // starts all stop together afterwards.
        m_server = new QProcess(this);
        m_server->setWorkingDirectory(directory);
        m_server->setProcessChannelMode(QProcess::MergedChannels);
        m_server->setStandardInputFile(QProcess::nullDevice());
        m_server->setChildProcessModifier([] { ::setsid(); });
        QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
        environment.insert("BROWSER", "none");
        environment.insert("CI", "1");
        m_server->setProcessEnvironment(environment);
        connect(m_server, &QProcess::readyRead, m_server, [server = m_server] { server->readAll(); });
        m_server->start("sh", {"-c", command});
    }
    // Wait for the address to accept connections, up to 90 seconds.
    auto attempts = std::make_shared<int>(0);
    auto timer = new QTimer(this);
    timer->setInterval(1000);
    connect(timer, &QTimer::timeout, this, [this, timer, attempts, target, url, path] {
        auto *socket = new QTcpSocket(this);
        connect(socket, &QTcpSocket::connected, this, [this, timer, socket, url, path] {
            socket->deleteLater();
            if (!timer->isActive())
                return;
            timer->stop();
            timer->deleteLater();
            // A moment for the page's own scripts to settle.
            QTimer::singleShot(1500, this, [this, url, path] { shoot(url, path); });
        });
        connect(socket, &QTcpSocket::errorOccurred, socket, &QObject::deleteLater);
        socket->connectToHost(target.host(), target.port(target.scheme() == "https" ? 443 : 80));
        if (++*attempts > 90 && timer->isActive()) {
            timer->stop();
            timer->deleteLater();
            stopServer();
            emit previewed({}, tr("Nothing answered at %1 within 90 seconds.").arg(url));
        }
    });
    timer->start();
}

void Gates::shoot(const QString &url, const QString &path) {
    QFile::remove(path);
    auto *shot = new QProcess(this);
    shot->setProcessChannelMode(QProcess::MergedChannels);
    connect(shot, &QProcess::finished, this, [this, shot, path] {
        shot->deleteLater();
        stopServer();
        if (QFile::exists(path))
            emit previewed(path, {});
        else
            emit previewed({}, tr("The browser didn't take the screenshot: %1").arg(QString::fromUtf8(shot->readAll()).trimmed().right(300)));
    });
    QTimer::singleShot(60000, shot, [shot] { shot->kill(); });
    // A fixed wait rather than "until the network is quiet": dev servers keep
    // live-reload connections open, so it never is.
    shot->start(browser(), {"--headless=new", "--disable-gpu", "--hide-scrollbars", "--window-size=1280,800",
                            "--timeout=6000", "--screenshot=" + path, url});
}

void Gates::stopServer() {
    if (!m_server)
        return;
    const qint64 pid = m_server->processId();
    m_server->disconnect(this);
    if (pid > 0) {
        ::kill(-pid_t(pid), SIGTERM);
        if (!m_server->waitForFinished(3000))
            ::kill(-pid_t(pid), SIGKILL);
    }
    m_server->waitForFinished(1000);
    m_server->deleteLater();
    m_server = nullptr;
}

QVariantList Gates::detect(const QString &directory) {
    QVariantList gates;
    const QDir dir(directory);
    auto add = [&gates](const QString &name, const QString &command) {
        gates.append(QVariantMap{{"name", name}, {"command", command}});
    };

    // JavaScript: the package manager its lockfile names, and the scripts it
    // has. npm's placeholder test script doesn't count.
    QFile package(dir.filePath("package.json"));
    if (package.open(QIODevice::ReadOnly)) {
        const QJsonObject scripts = QJsonDocument::fromJson(package.readAll()).object().value("scripts").toObject();
        const QString runner = dir.exists("pnpm-lock.yaml") ? "pnpm" : dir.exists("yarn.lock") ? "yarn"
                             : dir.exists("bun.lockb") || dir.exists("bun.lock") ? "bun" : "npm";
        const QString runScript = runner == "npm" ? "npm run" : runner + " run";
        if (scripts.contains("build"))
            add("build", runScript + " build");
        if (scripts.contains("lint"))
            add("lint", runScript + " lint");
        if (scripts.contains("typecheck"))
            add("typecheck", runScript + " typecheck");
        const QString test = scripts.value("test").toString();
        if (!test.isEmpty() && !test.contains("no test specified"))
            add("test", runner == "npm" ? "npm test" : runner + " test");
        return gates;
    }
    if (dir.exists("Cargo.toml")) {
        add("build", "cargo build --quiet");
        add("test", "cargo test --quiet");
        return gates;
    }
    if (dir.exists("go.mod")) {
        add("build", "go build ./...");
        add("test", "go test ./...");
        return gates;
    }
    // A project's own test script (Omarchy apps keep one).
    if (QFileInfo(dir.filePath("bin/test")).isExecutable()) {
        add("test", "bin/test");
        return gates;
    }
    QFile makefile(dir.filePath("Makefile"));
    if (makefile.open(QIODevice::ReadOnly)) {
        const QString text = QString::fromUtf8(makefile.readAll());
        static const QRegularExpression target("^(test|check|lint)\\s*:", QRegularExpression::MultilineOption);
        auto match = target.globalMatch(text);
        while (match.hasNext()) {
            const QString name = match.next().captured(1);
            add(name, "make " + name);
        }
        if (!gates.isEmpty())
            return gates;
    }
    if (dir.exists("pyproject.toml") || dir.exists("pytest.ini") || dir.exists("setup.cfg") || dir.exists("tests")
        || !dir.entryList({"test_*.py"}, QDir::Files).isEmpty()) {
        // pytest when it's set up; otherwise the standard library's runner.
        QFile pyproject(dir.filePath("pyproject.toml"));
        const bool pytest = dir.exists("pytest.ini") || (pyproject.open(QIODevice::ReadOnly) && pyproject.readAll().contains("pytest"));
        add("test", pytest ? "python3 -m pytest -q" : "python3 -m unittest discover -q");
    }
    return gates;
}

void Gates::run(const QString &directory, const QVariantList &gates, int timeoutSeconds) {
    stop();
    m_directory = directory;
    m_queue = gates;
    m_results.clear();
    m_timeout = timeoutSeconds;
    next();
}

void Gates::stop() {
    if (m_process) {
        m_process->disconnect(this);
        m_process->kill();
        m_process->waitForFinished(2000);
        m_process->deleteLater();
    }
    m_process = nullptr;
    m_queue.clear();
}

void Gates::next() {
    if (m_queue.isEmpty()) {
        m_process = nullptr;
        emit finished(m_results);
        return;
    }
    const QVariantMap gate = m_queue.takeFirst().toMap();
    auto *process = new QProcess(this);
    m_process = process;
    process->setWorkingDirectory(m_directory);
    process->setProcessChannelMode(QProcess::MergedChannels);
    process->setStandardInputFile(QProcess::nullDevice());
    QProcessEnvironment environment = QProcessEnvironment::systemEnvironment();
    // Tools that would otherwise wait for a person or paint for a terminal.
    environment.insert("CI", "1");
    environment.insert("FORCE_COLOR", "0");
    environment.insert("NO_COLOR", "1");
    process->setProcessEnvironment(environment);
    auto clock = std::make_shared<QElapsedTimer>();
    clock->start();
    auto output = std::make_shared<QByteArray>();
    connect(process, &QProcess::readyRead, this, [process, output] {
        *output += process->readAll();
        if (output->size() > OutputTail * 4)
            *output = output->right(OutputTail * 2);
    });
    auto timer = new QTimer(process);
    timer->setSingleShot(true);
    connect(timer, &QTimer::timeout, process, [process, output] {
        *output += QString("\n[Fireteam stopped this gate: it ran past its time limit.]\n").toUtf8();
        process->kill();
    });
    timer->start(m_timeout * 1000);
    auto done = [this, process, gate, clock, output](bool passed) {
        *output += process->readAll();
        m_results.append(QVariantMap{{"name", gate.value("name")}, {"command", gate.value("command")},
                                     {"passed", passed}, {"seconds", int(clock->elapsed() / 1000)},
                                     {"output", QString::fromUtf8(output->right(OutputTail)).trimmed()}});
        process->deleteLater();
        next();
    };
    connect(process, &QProcess::finished, this, [process, done](int code, QProcess::ExitStatus status) {
        Q_UNUSED(process);
        done(status == QProcess::NormalExit && code == 0);
    });
    connect(process, &QProcess::errorOccurred, this, [done](QProcess::ProcessError error) {
        if (error == QProcess::FailedToStart)
            done(false);
    });
    emit started(gate.value("name").toString());
    process->start("sh", {"-c", gate.value("command").toString()});
}
