#include "graphs.h"

#include <QCryptographicHash>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QHash>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QPointF>
#include <QRandomGenerator>
#include <QStandardPaths>
#include <QtMath>
#include <algorithm>
#include <numeric>

namespace Graphs {

QString installDirectory(const QString &dataDirectory) { return dataDirectory + "/graphify"; }

QString executable(const QString &dataDirectory) {
    const QString configured = qEnvironmentVariable("FIRETEAM_GRAPHIFY");
    if (!configured.isEmpty())
        return QFileInfo(configured).isExecutable() ? configured : QString();
    const QString onPath = QStandardPaths::findExecutable("graphify");
    if (!onPath.isEmpty())
        return onPath;
    const QString own = installDirectory(dataDirectory) + "/bin/graphify";
    return QFileInfo(own).isExecutable() ? own : QString();
}

QString outputDirectory(const QString &dataDirectory, const QString &project) {
    const QString hash = QCryptographicHash::hash(QDir::cleanPath(project).toUtf8(), QCryptographicHash::Sha1).toHex().left(16);
    return dataDirectory + "/graphs/" + hash;
}

QString graphFile(const QString &dataDirectory, const QString &project) {
    return outputDirectory(dataDirectory, project) + "/graphify-out/graph.json";
}

QStringList buildArguments(const QString &dataDirectory, const QString &project) {
    // Code only: read locally from the syntax trees, with no model and no key.
    return {"extract", QDir::cleanPath(project), "--code-only", "--out", outputDirectory(dataDirectory, project)};
}

static QJsonObject readJson(const QString &path) {
    QFile file(path);
    if (!file.open(QIODevice::ReadOnly))
        return {};
    return QJsonDocument::fromJson(file.readAll()).object();
}

// Fruchterman-Reingold, seeded so the same graph lands the same way, with
// files of one community starting together and pulled gently to its centre.
static void layout(QList<QPointF> &points, const QList<int> &community, const QList<QPair<int, int>> &edges,
                   const QList<double> &weights) {
    const int n = points.size();
    if (n == 0)
        return;
    QRandomGenerator random(7);
    QHash<int, int> communityIndex;
    for (int c : community)
        if (!communityIndex.contains(c))
            communityIndex.insert(c, communityIndex.size());
    const int groups = std::max<qsizetype>(1, communityIndex.size());
    QList<QPointF> anchors;
    for (int g = 0; g < groups; ++g) {
        const double angle = 2 * M_PI * g / groups;
        anchors << QPointF(std::cos(angle) * 0.35, std::sin(angle) * 0.35);
    }
    for (int i = 0; i < n; ++i)
        points[i] = anchors[communityIndex.value(community[i])]
                    + QPointF(random.bounded(0.2) - 0.1, random.bounded(0.2) - 0.1);

    const double k = std::sqrt(1.0 / n) * 0.9;
    double temperature = 0.1;
    const int iterations = n > 400 ? 150 : 300;
    QList<QPointF> displacement(n);
    for (int step = 0; step < iterations; ++step) {
        std::fill(displacement.begin(), displacement.end(), QPointF());
        for (int i = 0; i < n; ++i)
            for (int j = i + 1; j < n; ++j) {
                QPointF delta = points[i] - points[j];
                double distance = std::max(1e-4, std::hypot(delta.x(), delta.y()));
                const QPointF push = delta / distance * (k * k / distance);
                displacement[i] += push;
                displacement[j] -= push;
            }
        for (int e = 0; e < edges.size(); ++e) {
            const int a = edges[e].first, b = edges[e].second;
            QPointF delta = points[a] - points[b];
            double distance = std::max(1e-4, std::hypot(delta.x(), delta.y()));
            const QPointF pull = delta / distance * (distance * distance / k) * std::min(3.0, 0.5 + std::log1p(weights[e]) * 0.5);
            displacement[a] -= pull;
            displacement[b] += pull;
        }
        for (int i = 0; i < n; ++i) {
            // A little gravity to the community's anchor and to the middle.
            displacement[i] += (anchors[communityIndex.value(community[i])] - points[i]) * 0.6 * k;
            displacement[i] -= points[i] * 0.3 * k;
            const double length = std::max(1e-6, std::hypot(displacement[i].x(), displacement[i].y()));
            points[i] += displacement[i] / length * std::min(length, temperature);
        }
        temperature *= 0.985;
    }
    // Files linked to nothing (scripts, assets) would drift to the edges and
    // squeeze the rest, so they're set in a row along the foot instead.
    QList<int> linked(n, 0);
    for (const auto &edge : edges) {
        linked[edge.first] += 1;
        linked[edge.second] += 1;
    }
    QList<int> loose;
    double minX = 1e9, minY = 1e9, maxX = -1e9, maxY = -1e9;
    for (int i = 0; i < n; ++i) {
        if (linked[i] == 0 && n > 1) {
            loose << i;
            continue;
        }
        minX = std::min(minX, points[i].x()); maxX = std::max(maxX, points[i].x());
        minY = std::min(minY, points[i].y()); maxY = std::max(maxY, points[i].y());
    }
    // Into 0..1 with a margin, keeping the aspect; the row takes the foot.
    const double room = loose.isEmpty() ? 0.9 : 0.8;
    const double span = std::max({maxX - minX, maxY - minY, 1e-6});
    for (int i = 0; i < n; ++i)
        if (linked[i] > 0 || n == 1)
            points[i] = QPointF(0.05 + 0.9 * (points[i].x() - minX) / span + 0.45 * (1 - (maxX - minX) / span),
                                0.05 + room * (points[i].y() - minY) / span + room / 2 * (1 - (maxY - minY) / span));
    for (int k = 0; k < loose.size(); ++k)
        points[loose[k]] = QPointF(0.05 + 0.9 * (k + 0.5) / loose.size(), 0.95);
}

QVariantMap view(const QString &graphJson) {
    const QJsonObject graph = readJson(graphJson);
    const QJsonArray nodes = graph.value("nodes").toArray();
    if (nodes.isEmpty())
        return {};
    const QJsonArray links = graph.value("links").toArray();

    // Symbols by file; external concepts (cstdio, QString) belong to no file.
    QHash<QString, QString> fileOf;
    QHash<QString, int> fileIndex;
    QStringList paths;
    QList<int> symbols;
    QList<QHash<int, int>> communityVotes;
    QList<QList<QPair<int, QString>>> named;  // degree, label
    QHash<QString, int> degree;
    for (const QJsonValue &value : links) {
        const QJsonObject link = value.toObject();
        degree[link.value("source").toString()] += 1;
        degree[link.value("target").toString()] += 1;
    }
    int symbolCount = 0;
    for (const QJsonValue &value : nodes) {
        const QJsonObject node = value.toObject();
        const QString path = node.value("source_file").toString();
        if (path.isEmpty())
            continue;
        const QString id = node.value("id").toString();
        fileOf.insert(id, path);
        if (!fileIndex.contains(path)) {
            fileIndex.insert(path, paths.size());
            paths << path;
            symbols << 0;
            communityVotes << QHash<int, int>();
            named << QList<QPair<int, QString>>();
        }
        const int f = fileIndex.value(path);
        symbols[f] += 1;
        ++symbolCount;
        communityVotes[f][node.value("community").toInt()] += 1;
        named[f] << qMakePair(degree.value(id), node.value("label").toString());
    }

    // Links between files, summed.
    QHash<quint64, double> between;
    QList<int> fileDegree(paths.size(), 0);
    for (const QJsonValue &value : links) {
        const QJsonObject link = value.toObject();
        const QString a = fileOf.value(link.value("source").toString()), b = fileOf.value(link.value("target").toString());
        if (a.isEmpty() || b.isEmpty() || a == b)
            continue;
        int i = fileIndex.value(a), j = fileIndex.value(b);
        if (i > j)
            std::swap(i, j);
        between[(quint64(i) << 32) | quint64(j)] += link.value("weight").toDouble(1);
    }
    QList<QPair<int, int>> edges;
    QList<double> weights;
    QVariantList linkList;
    for (auto it = between.cbegin(); it != between.cend(); ++it) {
        const int a = int(it.key() >> 32), b = int(it.key() & 0xffffffff);
        edges << qMakePair(a, b);
        weights << it.value();
        fileDegree[a] += 1;
        fileDegree[b] += 1;
    }
    // In a stable order, so the same graph gives the same layout.
    QList<int> order(edges.size());
    std::iota(order.begin(), order.end(), 0);
    std::sort(order.begin(), order.end(), [&](int x, int y) { return edges[x] < edges[y]; });
    QList<QPair<int, int>> sortedEdges;
    QList<double> sortedWeights;
    for (int e : order) {
        sortedEdges << edges[e];
        sortedWeights << weights[e];
        linkList << QVariantMap{{"a", edges[e].first}, {"b", edges[e].second}, {"weight", weights[e]}};
    }

    QList<int> community;
    for (const auto &votes : communityVotes) {
        int best = 0, count = -1;
        for (auto it = votes.cbegin(); it != votes.cend(); ++it)
            if (it.value() > count || (it.value() == count && it.key() < best)) {
                best = it.key();
                count = it.value();
            }
        community << best;
    }
    QList<QPointF> points(paths.size());
    layout(points, community, sortedEdges, sortedWeights);

    QVariantList files;
    for (int f = 0; f < paths.size(); ++f) {
        auto top = named[f];
        std::sort(top.begin(), top.end(), [](const auto &x, const auto &y) { return x.first > y.first; });
        QStringList labels;
        for (int t = 0; t < top.size() && labels.size() < 6; ++t)
            if (!labels.contains(top[t].second))
                labels << top[t].second;
        files << QVariantMap{{"path", paths[f]}, {"symbols", symbols[f]}, {"community", community[f]},
                             {"x", points[f].x()}, {"y", points[f].y()}, {"degree", fileDegree[f]}, {"top", labels}};
    }

    // A community is named for its biggest file.
    QHash<int, QPair<int, QString>> biggest;
    QHash<int, int> sizes;
    for (int f = 0; f < paths.size(); ++f) {
        sizes[community[f]] += 1;
        if (!biggest.contains(community[f]) || symbols[f] > biggest[community[f]].first)
            biggest[community[f]] = qMakePair(symbols[f], QFileInfo(paths[f]).completeBaseName());
    }
    QList<int> communityIds = sizes.keys();
    std::sort(communityIds.begin(), communityIds.end(), [&](int x, int y) { return sizes[x] > sizes[y] || (sizes[x] == sizes[y] && x < y); });
    QVariantList communities;
    for (int id : communityIds)
        communities << QVariantMap{{"id", id}, {"label", biggest[id].second}, {"size", sizes[id]}};

    // Hubs, from graphify's own analysis beside the graph.
    QVariantList hubs;
    const QJsonObject analysis = readJson(QFileInfo(graphJson).absolutePath() + "/.graphify_analysis.json");
    for (const QJsonValue &value : analysis.value("gods").toArray()) {
        const QJsonObject god = value.toObject();
        hubs << QVariantMap{{"label", god.value("label").toString()}, {"path", fileOf.value(god.value("id").toString())},
                            {"degree", god.value("degree").toInt()}};
        if (hubs.size() >= 8)
            break;
    }

    return {{"files", files}, {"links", linkList}, {"communities", communities}, {"hubs", hubs},
            {"stats", QVariantMap{{"files", paths.size()}, {"symbols", symbolCount}, {"links", linkList.size()},
                                  {"communities", communities.size()}}},
            {"commit", graph.value("built_at_commit").toString()},
            {"builtAt", QFileInfo(graphJson).lastModified().toString(Qt::ISODate)}};
}

QVariantMap fileDetail(const QString &graphJson, const QString &path) {
    const QJsonObject graph = readJson(graphJson);
    QHash<QString, QString> fileOf;
    QHash<QString, int> degree;
    for (const QJsonValue &value : graph.value("links").toArray()) {
        degree[value.toObject().value("source").toString()] += 1;
        degree[value.toObject().value("target").toString()] += 1;
    }
    QList<QVariantMap> symbols;
    for (const QJsonValue &value : graph.value("nodes").toArray()) {
        const QJsonObject node = value.toObject();
        const QString id = node.value("id").toString();
        fileOf.insert(id, node.value("source_file").toString());
        if (node.value("source_file").toString() == path)
            symbols << QVariantMap{{"label", node.value("label").toString()},
                                   {"line", node.value("source_location").toString().mid(1).toInt()},
                                   {"degree", degree.value(id)}};
    }
    std::sort(symbols.begin(), symbols.end(), [](const QVariantMap &a, const QVariantMap &b) {
        return a.value("degree").toInt() > b.value("degree").toInt();
    });
    QHash<QString, double> neighbours;
    for (const QJsonValue &value : graph.value("links").toArray()) {
        const QJsonObject link = value.toObject();
        const QString a = fileOf.value(link.value("source").toString()), b = fileOf.value(link.value("target").toString());
        if (a.isEmpty() || b.isEmpty() || a == b)
            continue;
        if (a == path)
            neighbours[b] += 1;
        else if (b == path)
            neighbours[a] += 1;
    }
    QList<QPair<double, QString>> ranked;
    for (auto it = neighbours.cbegin(); it != neighbours.cend(); ++it)
        ranked << qMakePair(it.value(), it.key());
    std::sort(ranked.begin(), ranked.end(), [](const auto &x, const auto &y) { return x.first > y.first || (x.first == y.first && x.second < y.second); });
    QVariantList symbolList, neighbourList;
    for (int i = 0; i < symbols.size() && i < 40; ++i)
        symbolList << symbols[i];
    for (int i = 0; i < ranked.size() && i < 12; ++i)
        neighbourList << QVariantMap{{"path", ranked[i].second}, {"weight", ranked[i].first}};
    return {{"symbols", symbolList}, {"neighbours", neighbourList}};
}

QString brief(const QVariantMap &view, const QString &graphJson, const QString &executable) {
    if (view.isEmpty())
        return {};
    const QVariantMap stats = view.value("stats").toMap();
    QStringList lines{QString("PROJECT MAP: a knowledge graph of this project's code (%1 files, %2 symbols), built by graphify.")
                          .arg(stats.value("files").toInt()).arg(stats.value("symbols").toInt())};
    QStringList hubs;
    for (const QVariant &value : view.value("hubs").toList()) {
        const QVariantMap hub = value.toMap();
        hubs << QString("%1 (%2, %3 links)").arg(hub.value("label").toString(), hub.value("path").toString())
                    .arg(hub.value("degree").toInt());
        if (hubs.size() >= 6)
            break;
    }
    if (!hubs.isEmpty())
        lines << "Hubs, the most connected code: " + hubs.join("; ") + ".";
    // Each community with its files, biggest first.
    QHash<int, QStringList> members;
    for (const QVariant &value : view.value("files").toList()) {
        const QVariantMap file = value.toMap();
        members[file.value("community").toInt()] << file.value("path").toString();
    }
    QStringList groups;
    for (const QVariant &value : view.value("communities").toList()) {
        const QVariantMap community = value.toMap();
        QStringList files = members.value(community.value("id").toInt());
        const int more = files.size() - 5;
        files = files.mid(0, 5);
        groups << "- " + files.join(", ") + (more > 0 ? QString(" and %1 more").arg(more) : QString());
        if (groups.size() >= 8)
            break;
    }
    if (!groups.isEmpty())
        lines << "Files that work together:\n" + groups.join('\n');
    if (!executable.isEmpty())
        lines << QString("To find code or see what a change reaches, ask the graph instead of reading widely: "
                         "%1 query \"<question>\" --graph %2, %1 explain \"<symbol>\" --graph %2, or "
                         "%1 affected \"<symbol>\" --graph %2. The graph is from the last build and may lag your edits.")
                     .arg(executable, graphJson);
    return lines.join('\n');
}

QStringList allowedRules(const QString &executable) {
    if (executable.isEmpty())
        return {};
    QStringList rules;
    for (const char *command : {"query", "explain", "affected", "path", "god-nodes"})
        rules << QString("Bash(%1 %2:*)").arg(executable, QLatin1String(command));
    return rules;
}

}
