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
    // Only redirect when source and destination are on the same drive root.
    // On Windows, cross-drive paths cause Gradle task-creation failures.
    val srcRoot = project.projectDir.absoluteFile.toPath().root
    val dstRoot = newSubprojectBuildDir.asFile.absoluteFile.toPath().root
    if (srcRoot == dstRoot) {
        project.layout.buildDirectory.value(newSubprojectBuildDir)
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
