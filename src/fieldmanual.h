#pragma once

#include <QString>
#include <QStringList>
#include <QVariantList>

// A project's field manual: lasting lessons about it (how to build and test
// it, its conventions and gotchas) gathered from operations that worked
// there, and passed to the operations that come after. One JSON file per
// project directory in Fireteam's data, never in the project itself, until
// the operator promotes lessons into its CLAUDE.md.
class FieldManual {
public:
    FieldManual(const QString &dataDirectory, const QString &projectDirectory);

    QString project() const { return m_project; }
    // [{id, text, source, added}], newest first.
    QVariantList lessons() const { return m_lessons; }
    // Adds lessons not already there (ignoring case and spacing); returns how
    // many were new.
    int add(const QStringList &texts, const QString &source);
    bool edit(const QString &id, const QString &text);
    bool remove(const QString &id);
    // The lessons as a block for a cycle prompt, at most limit of them.
    QString brief(int limit = 15) const;
    // Appends the chosen lessons to the project's CLAUDE.md, under a heading
    // of Fireteam's; returns the file's path, or empty on failure.
    QString promote(const QStringList &ids) const;
    bool save() const;

    // Every project with a manual: [{directory, count}].
    static QVariantList all(const QString &dataDirectory);

private:
    static QString key(const QString &text);

    QString m_path;
    QString m_project;
    QVariantList m_lessons;
};
