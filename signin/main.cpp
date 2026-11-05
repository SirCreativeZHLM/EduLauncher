// Small browser window for the Microsoft school account sign-in.
// Usage: edulauncher-signin <start url> <redirect url prefix>
// Prints the url the sign-in redirected to and exits 0, exits 1 when the window is closed.
// Also used by the edulauncher script for dialogs:
//   edulauncher-signin --pick-apk          prints the chosen file, exits 1 on cancel
//   edulauncher-signin --message <text>    shows a message box
#include <QApplication>
#include <QCommandLineParser>
#include <QDesktopServices>
#include <QDir>
#include <QFileDialog>
#include <QHBoxLayout>
#include <QLabel>
#include <QLineEdit>
#include <QMessageBox>
#include <QPushButton>
#include <QRegularExpression>
#include <QStackedWidget>
#include <QStandardPaths>
#include <QVBoxLayout>
#include <QWebEnginePage>
#include <QWebEngineProfile>
#include <QWebEngineSettings>
#include <QWebEngineView>
#include <cstdio>

static bool finished = false;

static void finish(QString const &url) {
    printf("%s\n", url.toUtf8().constData());
    fflush(stdout);
    finished = true;
    QApplication::exit(0);
}

class SignInPage : public QWebEnginePage {
    QString redirectPrefix;

public:
    SignInPage(QWebEngineProfile *profile, QString redirectPrefix, QObject *parent) : QWebEnginePage(profile, parent), redirectPrefix(std::move(redirectPrefix)) {}

protected:
    bool acceptNavigationRequest(const QUrl &url, NavigationType, bool) override {
        auto str = url.toString(QUrl::FullyEncoded);
        if(str.startsWith(redirectPrefix)) {
            finish(str);
            return false;
        }
        return true;
    }

    // School sign-in pages sometimes open a popup, show it in the same window
    QWebEnginePage *createWindow(WebWindowType) override { return this; }
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
    // Google and some school sign-in pages refuse browsers that say they are embedded, look like plain Chrome
    profile.setHttpUserAgent(profile.httpUserAgent().remove(QRegularExpression(" QtWebEngine/[^ ]+")));
    profile.settings()->setAttribute(QWebEngineSettings::JavascriptCanOpenWindows, true);

    auto startUrl = QUrl(parser.positionalArguments()[0]);
    auto redirectPrefix = parser.positionalArguments()[1];

    QWidget window;
    window.setWindowTitle("Sign in to Minecraft Education");
    auto layout = new QVBoxLayout(&window);
    layout->setContentsMargins(0, 0, 0, 0);
    layout->setSpacing(0);

    // Bar to switch to the system browser when the sign-in page does not work in this window
    auto bar = new QStackedWidget;
    auto offer = new QWidget;
    auto offerLayout = new QHBoxLayout(offer);
    offerLayout->addWidget(new QLabel("Stuck on your school's page?"), 1);
    auto useBrowser = new QPushButton("Use my web browser instead");
    offerLayout->addWidget(useBrowser);
    bar->addWidget(offer);

    auto paste = new QWidget;
    auto pasteLayout = new QVBoxLayout(paste);
    auto pasteLabel = new QLabel("Sign in in the browser window that opened. When it ends on a blank page, copy the whole address "
                                 "from the address bar and paste it here:");
    pasteLabel->setWordWrap(true);
    pasteLayout->addWidget(pasteLabel);
    auto pasteRow = new QHBoxLayout;
    auto pasteEdit = new QLineEdit;
    pasteEdit->setPlaceholderText(redirectPrefix + "?code=...");
    pasteRow->addWidget(pasteEdit, 1);
    auto pasteDone = new QPushButton("Continue");
    pasteRow->addWidget(pasteDone);
    pasteLayout->addLayout(pasteRow);
    auto pasteError = new QLabel;
    pasteError->setStyleSheet("color: #c0392b");
    pasteLayout->addWidget(pasteError);
    bar->addWidget(paste);
    bar->setSizePolicy(QSizePolicy::Preferred, QSizePolicy::Maximum);
    layout->addWidget(bar);

    auto view = new QWebEngineView;
    auto page = new SignInPage(&profile, redirectPrefix, view);
    view->setPage(page);
    layout->addWidget(view, 1);
    QObject::connect(page, &QWebEnginePage::titleChanged, &window, [&window](const QString &title) {
        window.setWindowTitle(title.isEmpty() ? "Sign in to Minecraft Education" : title + " - Minecraft Education sign-in");
    });
    QObject::connect(useBrowser, &QPushButton::clicked, &window, [&] {
        QDesktopServices::openUrl(startUrl);
        bar->setCurrentWidget(paste);
        pasteEdit->setFocus();
    });
    auto submit = [&] {
        auto text = pasteEdit->text().trimmed();
        if(!text.startsWith(redirectPrefix) || !text.contains("code=")) {
            pasteError->setText("That is not the right address yet. It starts with " + redirectPrefix + " and contains code=");
            return;
        }
        finish(text);
    };
    QObject::connect(pasteDone, &QPushButton::clicked, &window, submit);
    QObject::connect(pasteEdit, &QLineEdit::returnPressed, &window, submit);

    window.resize(520, 760);
    view->load(startUrl);
    window.show();

    app.exec();
    // The page has to go before its profile
    view->setPage(nullptr);
    delete page;
    // Closing the window without finishing counts as cancel
    return finished ? 0 : 1;
}
