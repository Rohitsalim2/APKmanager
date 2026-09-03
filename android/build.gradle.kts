allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val buildDir = File(rootDir, "../build")
rootProject.extra["buildDir"] = buildDir

subprojects {
    val projectBuildDir = File(buildDir, name)
    extra["buildDir"] = projectBuildDir
}

subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.buildDir)
}