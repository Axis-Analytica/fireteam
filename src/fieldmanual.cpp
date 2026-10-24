#include "fieldmanual.h"

#include <QCryptographicHash>
#include <QDateTime>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QSaveFile>
#include <QSet>
#include <QUuid>

static QString manualPath(const QString &dataDirectory, const QString &project) {
    const QString hash = QCryptographicHash::hash(QDir::cleanPath(project).toUtf8(), QCryptographicHash::Sha1).toHex().left(16);
    return dataDirectory + "/manuals/" + hash + ".json";
}

FieldManual::FieldManual(const QString &dataDirectory, const QString &projectDirectory)
    : m_path(manualPath(dataDirectory, projectDirectory)), m_project(QDir::cleanPath(projectDirectory)) {
    QFile file(m_path);
    if (file.open(QIODevice::ReadOnly))
        m_lessons = QJsonDocument::fromJson(file.readAll()).object().value("lessons").toArray().toVariantList();
}

QString FieldManual::key(const QString &text) {
    return text.simplified().toLower().remove(QRegularExpression("[^a-z0-9 ]"));
}

int FieldManual::add(const QStringList &texts, const QString &source) {
    QSet<QString> known;
    for (const QVariant &lesson : m_lessons)
        known.insert(key(lesson.toMap().value("text").toString()));
    int added = 0;
    for (const QString &raw : texts) {
        const QString text = raw.simplified().left(400);
        if (text.size() < 8 || known.contains(key(text)))
            continue;
        known.insert(key(text));
        m_lessons.prepend(QVariantMap{{"id", QUuid::createUuid().toString(QUuid::WithoutBraces).left(8)}, {"text", text},
                                      {"source", source}, {"added", QDateTime::currentDateTime().toString(Qt::ISODate)}});
        ++added;
    }
    // A manual is read before every operation, so it stays short.
    if (m_lessons.size() > 60)
        m_lessons = m_lessons.mid(0, 60);
    return added;
}

bool FieldManual::edit(const QString &id, const QString &text) {
    for (QVariant &value : m_lessons) {
        QVariantMap lesson = value.toMap();
        if (lesson.value("id") != id)
            continue;
        if (text.simplified().isEmpty())
            return remove(id);
        lesson.insert("text", text.simplified().left(400));
        value = lesson;
        return true;
    }
    return false;
}

bool FieldManual::remove(const QString &id) {
    for (int i = 0; i < m_lessons.size(); ++i)
        if (m_lessons.at(i).toMap().value("id") == id) {
            m_lessons.removeAt(i);
            return true;
        }
    return false;
}

QString FieldManual::brief(int limit) const {
    if (m_lessons.isEmpty())
        return {};
    QStringList lines{"FIELD MANUAL: what earlier operations in this project learned. Trust it unless the project "
                      "shows otherwise, and say in your debrief if any of it is wrong."};
    for (int i = 0; i < m_lessons.size() && i < limit; ++i)
        lines << "- " + m_lessons.at(i).toMap().value("text").toString();
    return lines.join('\n');
}

QString FieldManual::promote(const QStringList &ids) const {
    QStringList chosen;
    for (const QVariant &lesson : m_lessons)
        if (ids.contains(lesson.toMap().value("id").toString()))
            chosen << "- " + lesson.toMap().value("text").toString();
    if (chosen.isEmpty())
        return {};
    const QString path = m_project + "/CLAUDE.md";
    QFile existing(path);
    QString text;
    if (existing.open(QIODevice::ReadOnly))
        text = QString::fromUtf8(existing.readAll());
    existing.close();
    // Under Fireteam's own heading, added to rather than repeated.
    const QString heading = "## Notes from Fireteam";
    QStringList fresh;
    for (const QString &line : chosen)
        if (!text.contains(line))
            fresh << line;
    if (fresh.isEmpty())
        return path;
    if (text.contains(heading)) {
        const qsizetype at = text.indexOf(heading) + heading.size();
        const qsizetype next = text.indexOf(QRegularExpression("\n## "), at);
        const qsizetype end = next < 0 ? text.size() : next;
        QString section = text.mid(at, end - at);
        while (section.endsWith('\n'))
            section.chop(1);
        text = text.left(at) + section + "\n" + fresh.join('\n') + "\n" + text.mid(end);
    } else {
        if (!text.isEmpty() && !text.endsWith("\n\n"))
            text += text.endsWith('\n') ? "\n" : "\n\n";
        text += heading + "\n\nLessons from Fireteam operations in this project.\n\n" + fresh.join('\n') + "\n";
    }
    QSaveFile file(path);
    if (!file.open(QIODevice::WriteOnly))
        return {};
    file.write(text.toUtf8());
    return file.commit() ? path : QString();
}

bool FieldManual::save() const {
    QDir().mkpath(QFileInfo(m_path).absolutePath());
    QSaveFile file(m_path);
    if (!file.open(QIODevice::WriteOnly))
        return false;
    file.write(QJsonDocument(QJsonObject{{"directory", m_project}, {"lessons", QJsonArray::fromVariantList(m_lessons)}}).toJson());
    return file.commit();
}

QVariantList FieldManual::all(const QString &dataDirectory) {
    QVariantList list;
    const QDir dir(dataDirectory + "/manuals");
    for (const QString &name : dir.entryList({"*.json"}, QDir::Files)) {
        QFile file(dir.filePath(name));
        if (!file.open(QIODevice::ReadOnly))
            continue;
        const QJsonObject manual = QJsonDocument::fromJson(file.readAll()).object();
        const int count = manual.value("lessons").toArray().size();
        if (count > 0)
            list.append(QVariantMap{{"directory", manual.value("directory").toString()}, {"count", count}});
    }
    return list;
}
