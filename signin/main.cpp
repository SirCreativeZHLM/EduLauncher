// Small browser window for the Microsoft school account sign-in.
// Usage: edulauncher-signin <start url> <redirect url prefix>
// Prints the url the sign-in redirected to and exits 0, exits 1 when the window is closed.
// Also used by the edulauncher script for dialogs:
//   edulauncher-signin --pick-apk          prints the chosen file, exits 1 on cancel
//   edulauncher-signin --message <text>    shows a message box
#include <QApplication>
#include <QCommandLineParser>
#include <QDir>
#include <QFileDialog>
#include <QMessageBox>
#include <QStandardPaths>
#include <QWebEnginePage>
#include <QWebEngineProfile>
#include <QWebEngineView>
#include <cstdio>

static bool finished = false;

class SignInPage : public QWebEnginePage {
    QString redirectPrefix;

public:
    SignInPage(QWebEngineProfile *profile, QString redirectPrefix, QObject *parent) : QWebEnginePage(profile, parent), redirectPrefix(std::move(redirectPrefix)) {}

protected:
    bool acceptNavigationRequest(const QUrl &url, NavigationType, bool) override {
        auto str = url.toString(QUrl::FullyEncoded);
        if(str.startsWith(redirectPrefix)) {
            printf("%s\n", str.toUtf8().constData());
            fflush(stdout);
            finished = true;
            QApplication::exit(0);
            return false;
        }
        return true;
    }
};

int main(int argc, char *argv[]) {
    QApplication app(argc, argv);
    QApplication::setApplicationName("edulauncher");
    QApplication::setApplicationDisplayName("Minecraft Education sign-in");
    QApplication::setDesktopFileName("io.github.sircreativezhlm.EduLauncher");

    if(argc >= 2 && QString(argv[1]) == "--pick-apk") {
        auto file = QFileDialog::getOpenFileName(nullptr, "Choose the Minecraft Education APK", QDir::homePath(),
                                                 "Android app (*.apk *.apks *.xapk *.apkm *.zip);;All files (*)");
        if(file.isEmpty())
            return 1;
        printf("%s\n", file.toUtf8().constData());
        return 0;
    }
    if(argc >= 3 && QString(argv[1]) == "--message") {
        QMessageBox::information(nullptr, "Minecraft Education", QString::fromUtf8(argv[2]));
        return 0;
    }

    QCommandLineParser parser;
    parser.addHelpOption();
    parser.addPositionalArgument("startUrl", "The sign-in page to open");
    parser.addPositionalArgument("redirectPrefix", "Finish when the page redirects to an url starting with this");
    parser.process(app);
    if(parser.positionalArguments().size() != 2) {
        parser.showHelp(2);
    }

    // Keep cookies so "Stay signed in" works across launches
    auto storage = QStandardPaths::writableLocation(QStandardPaths::AppDataLocation) + "/signin";
    QDir().mkpath(storage);
    QWebEngineProfile profile("edulauncher-signin");
    profile.setPersistentStoragePath(storage);
    profile.setCachePath(storage + "/cache");

    QWebEngineView view;
    auto page = new SignInPage(&profile, parser.positionalArguments()[1], &view);
    view.setPage(page);
    view.setWindowTitle("Sign in to Minecraft Education");
    QObject::connect(page, &QWebEnginePage::titleChanged, &view, [&view](const QString &title) {
        view.setWindowTitle(title.isEmpty() ? "Sign in to Minecraft Education" : title + " - Minecraft Education sign-in");
    });
    view.resize(520, 720);
    view.load(QUrl(parser.positionalArguments()[0]));
    view.show();

    app.exec();
    // The page has to go before its profile
    view.setPage(nullptr);
    delete page;
    // Closing the window without finishing counts as cancel
    return finished ? 0 : 1;
}
