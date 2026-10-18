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
// mapbox_maps_flutter 2.x skips Kotlin on AGP 9, expecting built-in Kotlin, which this template turns off;
// Flutter does not add it either, as the script mentions kotlin-android. Without this its `kotlin {}` block fails.
subprojects {
    if (name == "mapbox_maps_flutter") pluginManager.apply("org.jetbrains.kotlin.android")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
