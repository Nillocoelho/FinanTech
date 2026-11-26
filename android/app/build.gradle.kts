import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Chave de assinatura de release, lida de android/key.properties (fora do git).
// Formato esperado:
//   storePassword=...
//   keyPassword=...
//   keyAlias=...
//   storeFile=caminho/para/diazen-release.jks
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

android {
    namespace = "com.finantech.finantech"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Habilita o core library desugaring para suporte a APIs Java 8+
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // O namespace (pacote do código Kotlin) continua o antigo; só o id
        // publicado mudou. Instalações com o id anterior são outro app.
        applicationId = "br.com.diazen.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        // minSdk do Flutter é >= 21, então o multidex já é nativo (sem multiDexEnabled).
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // Sem android/key.properties (ex.: máquina de desenvolvimento), o
            // release cai na chave de debug só para `flutter run --release`
            // funcionar. NÃO distribua esse APK: a Play Store o recusa e um
            // APK com outra chave não atualiza o instalado (só desinstalando,
            // o que apaga o banco local).
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    // Core library desugaring para APIs Java 8+ em versões antigas do Android
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
