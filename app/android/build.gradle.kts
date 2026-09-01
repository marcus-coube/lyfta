allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
subprojects {
    project.evaluationDependsOn(":app")
}

// file_picker 11.0.3 vê AGP 9 e deixa de aplicar o plugin Kotlin, apostando no
// Kotlin embutido do AGP. Só que o template do Flutter o desliga
// (android.builtInKotlin=false) — e tem que desligar, senão connectivity_plus,
// que aplica kotlin-android à moda antiga, nem configura. Sem ninguém
// compilando o Kotlin do file_picker, o GeneratedPluginRegistrant não acha
// FilePickerPlugin. Aplicamos o plugin no lugar dele, só nesse módulo.
// Remover quando file_picker subir para uma versão que suporte AGP 9 — hoje
// barrada por flutter_secure_storage 9 (conflito de win32 5 vs 6).
subprojects {
    if (name == "file_picker") {
        plugins.withId("com.android.library") {
            apply(plugin = "org.jetbrains.kotlin.android")
            // O módulo compila Java em 17 (compileOptions do próprio plugin);
            // sem alinhar, o Kotlin sai em 21 e o Gradle recusa a mistura.
            tasks.withType<org.jetbrains.kotlin.gradle.tasks.KotlinCompile>()
                .configureEach {
                    compilerOptions.jvmTarget.set(
                        org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17,
                    )
                }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
