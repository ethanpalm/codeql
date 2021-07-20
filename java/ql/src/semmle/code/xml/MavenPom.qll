/**
 * Provides classes and predicates for working with Maven POM files and their content.
 */

import XML

/**
 * Normalize an absolute path, replacing all ".." and "." components.
 */
bindingset[path]
private string normalize(string path) {
  result = path.regexpReplaceAll("/\\.(/|$)", "/").regexpReplaceAll("/[^/]*/\\.\\.(/|$)", "/")
}

/**
 * An XML element that provides convenience access methods
 * to retrieve child XML elements named "groupId", "artifactId"
 * and "version", typically contained in Maven POM XML files.
 */
class ProtoPom extends XMLElement {
  /** Gets a child XML element named "groupId". */
  Group getGroup() { result = this.getAChild() }

  /** Gets a child XML element named "artifactId". */
  Artifact getArtifact() { result = this.getAChild() }

  /** Gets a child XML element named "version". */
  Version getVersion() { result = this.getAChild() }

  /**
   * Gets a string representing the version, or an empty string if no `version`
   * tag was provided.
   */
  string getVersionString() {
    if exists(getVersion().getValue()) then result = getVersion().getValue() else result = ""
  }

  /** Gets a Maven coordinate of the form `groupId:artifactId`. */
  string getShortCoordinate() {
    result = this.getGroup().getValue() + ":" + this.getArtifact().getValue()
  }
}

/**
 * An XML element named "project", with convenience access methods
 * to retrieve child XML elements named "version", "name" and "dependencies",
 * typically found at the top-level of Maven POM XML files.
 *
 * Access to child XML elements named "groupId" and "artifactId" is provided
 * via inherited methods from the super-class.
 */
class Pom extends ProtoPom {
  Pom() {
    this.getName() = "project" and
    // Ignore "dependency-reduced-pom" files - these are generated by the
    // Maven Shade Plugin, and duplicate existing POM files.
    this.getFile().getStem() != "dependency-reduced-pom"
  }

  override Group getGroup() {
    // For a project element, the group may be defined in the parent tags instead
    if not exists(super.getGroup())
    then exists(Parent p | p = this.getAChild() and result = p.getAChild())
    else result = super.getGroup()
  }

  /** Gets a Maven coordinate of the form `groupId:artifactId:version`. */
  string getCoordinate() {
    result =
      this.getGroup().getValue() + ":" + this.getArtifact().getValue() + ":" +
        this.getVersion().getValue()
  }

  /** Gets a child XML element named "name". */
  Named getNamed() { result = this.getAChild() }

  /** Gets a child XML element named "dependencies". */
  Dependencies getDependencies() { result = this.getAChild() }

  /** Gets a child XML element named "dependencyManagement". */
  DependencyManagement getDependencyManagement() { result = getAChild() }

  /** Gets a Dependency element for this POM. */
  Dependency getADependency() { result = getAChild().(Dependencies).getADependency() }

  /**
   * Gets a property defined in the `<properties>` section of this POM.
   */
  PomProperty getALocalProperty() { result = getAChild().(PomProperties).getAProperty() }

  /**
   * Gets a property value defined for this project, either in a local `<properties>` section, or
   * in the `<properties>` section of an ancestor POM.
   */
  PomProperty getAProperty() {
    result = getALocalProperty()
    or
    result = getParentPom().getAProperty() and
    not getALocalProperty().getName() = result.getName()
  }

  /**
   * Gets a property value defined for this project with the given name, either in a local
   * `<properties>` section, or in the `<properties>` section of an ancestor POM.
   */
  PomProperty getProperty(string name) {
    result.getName() = name and
    result = getAProperty()
  }

  /**
   * Gets a "project property" - for example, the groupId, name or packaging.
   */
  PomElement getProjectProperty() {
    (
      // It must either be a child of the POM, or a child of the parent node of the POM
      result = getAChild()
      or
      result = getParentPom().getAChild() and
      // The parent project property is not shadowed by a local project property
      not exists(PomElement p | p = getAChild() and p.getName() = result.getName())
    ) and
    // Can't be a property if it has children of its own
    not exists(result.getAChild())
  }

  /**
   * Resolve the given placeholder (if possible) in the static context of this POM. Resolution
   * occurs by considering the properties defined by this project or an ancestor project.
   */
  string resolvePlaceholder(string name) {
    if name.prefix(8) = "project."
    then
      exists(PomElement p |
        p = getProjectProperty() and
        "project." + p.getName() = name and
        result = p.getValue()
      )
    else
      exists(PomProperty prop |
        prop = getAProperty() and prop.getName() = name and result = prop.getValue()
      )
  }

  /**
   * Gets all the dependencies that are exported by this POM. An exported dependency is one that
   * is transitively available, i.e. one with scope "compile".
   */
  Dependency getAnExportedDependency() {
    result = getADependency() and result.getScope() = "compile"
  }

  /**
   * Gets a POM dependency that is exported by this POM. An exported dependency is one that
   * is transitively available, i.e. one with scope "compile".
   */
  Pom getAnExportedPom() { result = getAnExportedDependency().getPom() }

  /**
   * Gets the `<parent>` element of this POM, if any.
   */
  Parent getParentElement() { result = getAChild() }

  /**
   * Gets the POM referred to by the `<parent>` element of this POM, if any.
   */
  Pom getParentPom() { result = getParentElement().getPom() }

  /**
   * Gets the version specified for dependency `dep` in a `dependencyManagement`
   * section in this POM or one of its ancestors, or an empty string if no version
   * is specified.
   */
  string getVersionStringForDependency(Dependency dep) {
    if exists(getDependencyManagement().getDependency(dep))
    then result = getDependencyManagement().getDependency(dep).getVersionString()
    else
      if exists(getParentPom())
      then result = getParentPom().getVersionStringForDependency(dep)
      else result = ""
  }

  /**
   * Gets the folder considered to be the source directory for this POM, if present in the analyzed
   * snapshot.
   *
   * If the `<sourceDirectory>` property is set, the value will be used relative to the directory
   * containing this POM.
   */
  Folder getSourceDirectory() {
    exists(string relativePath |
      if exists(getProperty("sourceDirectory"))
      then
        // A custom source directory has been specified.
        relativePath = getProperty("sourceDirectory").getValue()
      else
        // The Maven default source directory.
        relativePath = "src"
    |
      // Resolve the relative path against the base directory for this POM
      result.getAbsolutePath() =
        normalize(getFile().getParentContainer().getAbsolutePath() + "/" + relativePath)
    )
  }

  /**
   * Gets a `RefType` contained in the source directory.
   */
  RefType getASourceRefType() { result.getFile().getParentContainer*() = getSourceDirectory() }
}

/**
 * An XML element named "dependency", as found in Maven POM XML files.
 *
 * Access to child XML elements named "groupId" and "artifactId" is provided
 * via inherited methods from the super-class.
 */
class Dependency extends ProtoPom {
  Dependency() { this.getName() = "dependency" }

  /**
   * Gets an XML element with the same Maven short coordinate
   * (of the form `groupId:artifactId`) as this element.
   */
  Pom getPom() { result.getShortCoordinate() = this.getShortCoordinate() }

  /**
   * Gets the jar file that Maven likely resolved this dependency to (if any).
   * See `MavenRepo.getAnArtifact(ProtoPom)` for how this match is determined.
   */
  File getJar() { exists(MavenRepo mr | result = mr.getAnArtifact(this)) }

  /**
   * Gets the scope of this dependency. If the `scope` tag is present, this will
   * be the string contents of that tag, otherwise it defaults to "compile".
   */
  string getScope() {
    if exists(getAChild().(Scope))
    then exists(Scope s | s = getAChild() and result = s.getValue())
    else result = "compile"
  }

  override string getVersionString() {
    if exists(getVersion())
    then result = super.getVersionString()
    else
      if exists(Pom p | this = p.getADependency())
      then
        exists(Pom p | this = p.getADependency() | result = p.getVersionStringForDependency(this))
      else result = ""
  }
}

/**
 * A Maven dependency element that represents an actual dependency from a given POM project.
 */
class PomDependency extends Dependency {
  PomDependency() {
    exists(Pom source |
      // This dependency must be a dependency of a POM - dependency tags can also appear in the
      // dependencyManagement section, where they do not directly contribute to the dependencies of
      // the containing POM.
      source.getADependency() = this and
      // Consider dependencies that can be used at compile time.
      (
        getScope() = "compile"
        or
        // Provided dependencies are like compile time dependencies except (a) they are not packaged
        // when creating the jar and (b) they are not transitive.
        getScope() = "provided"
        // We ignore "test" dependencies because they can be runtime or compile time dependencies
      )
    )
  }
}

/**
 * An XML element that provides access to its value string
 * in the context of Maven POM XML files.
 */
class PomElement extends XMLElement {
  /**
   * Gets the value associated with this element. If the value contains a placeholder only, it will be resolved.
   */
  string getValue() {
    exists(string s |
      s = allCharactersString() and
      if s.matches("${%")
      then
        // Resolve the placeholder in the parent POM
        result = getParent*().(Pom).resolvePlaceholder(s.substring(2, s.length() - 1))
      else result = s
    )
  }
}

/** An XML element named "groupId", as found in Maven POM XML files. */
class Group extends PomElement {
  Group() { this.getName() = "groupId" }
}

/** An XML element named "artifactId", as found in Maven POM XML files. */
class Artifact extends PomElement {
  Artifact() { this.getName() = "artifactId" }
}

/** An XML element named "parent", as found in Maven POM XML files. */
class Parent extends ProtoPom {
  Parent() { this.getName() = "parent" }

  Pom getPom() { result.getShortCoordinate() = this.getShortCoordinate() }
}

/** An XML element named "version", as found in Maven POM XML files. */
class Version extends PomElement {
  Version() { this.getName() = "version" }
}

/** An XML element named "name", as found in Maven POM XML files. */
class Named extends PomElement {
  Named() { this.getName() = "name" }
}

/** An XML element named "scope", as found in Maven POM XML files. */
class Scope extends PomElement {
  Scope() { this.getName() = "scope" }
}

/** An XML element named "dependencies", as found in Maven POM XML files. */
class Dependencies extends PomElement {
  Dependencies() { this.getName() = "dependencies" }

  Dependency getADependency() { result = this.getAChild() }
}

/** An XML element named "dependencyManagement", as found in Maven POM XML files. */
class DependencyManagement extends PomElement {
  DependencyManagement() { getName() = "dependencyManagement" }

  Dependencies getDependencies() { result = getAChild() }

  Dependency getADependency() { result = getDependencies().getADependency() }

  /**
   * Gets a dependency declared in this `dependencyManagement` element that has
   * the same (short) coordinates as `dep`.
   */
  Dependency getDependency(Dependency dep) {
    result = getADependency() and
    result.getShortCoordinate() = dep.getShortCoordinate()
  }
}

/**
 * An XML element named "properties", as found in Maven POM XML files.
 */
class PomProperties extends PomElement {
  PomProperties() { this.getName() = "properties" }

  PomProperty getAProperty() { result = this.getAChild() }
}

/**
 * An XML element that is the child of a PomProperties element, as found in Maven POM XML files.
 * Represents a single property.
 */
class PomProperty extends PomElement {
  PomProperty() { getParent() instanceof PomProperties }
}

/**
 * An XML element representing any kind of repository declared inside of a Maven POM XML file.
 */
class DeclaredRepository extends PomElement {
  DeclaredRepository() { this.getName() = ["repository", "snapshotRepository", "pluginRepository"] }

  /**
   * Gets the url for this repository. If the `url` tag is present, this will
   * be the string contents of that tag.
   */
  string getUrl() { result = getAChild("url").(PomElement).getValue() }
}

/**
 * A folder that represents a local Maven repository using the standard layout. Any folder called
 * "repository" with a parent name ".m2" is considered to be a Maven repository.
 */
class MavenRepo extends Folder {
  MavenRepo() { getBaseName() = "repository" and getParentContainer().getBaseName() = ".m2" }

  /**
   * Gets a Jar file contained within this repository.
   */
  File getAJarFile() { result = getAChildContainer*().(File) and result.getExtension() = "jar" }

  /**
   * Gets any jar artifacts in this repository that match the POM project definition. This is an
   * over approximation. For soft qualifiers (e.g. 1.0) precise matches are returned in preference
   * to artifact-only matches. For hard qualifiers (e.g. [1.0]) only precise matches are returned.
   * For all other qualifiers, all matches are returned regardless of version.
   */
  MavenRepoJar getAnArtifact(ProtoPom pom) {
    result = getAJarFile() and
    if exists(MavenRepoJar mrj | mrj.preciseMatch(pom)) or versionHardMatch(pom)
    then
      // Either a hard match qualifier, or soft and there is at least one precise match
      result.preciseMatch(pom)
    else result.artifactMatches(pom)
  }
}

/**
 * If this POM has a version string representing a "hard" match
 */
private predicate versionHardMatch(ProtoPom pom) {
  pom.getVersionString().regexpMatch("^\\[[^,\\[]*\\]$")
}

/**
 * A jar file inside a Maven repository.
 *
 * See: https://cwiki.apache.org/confluence/display/MAVENOLD/Repository+Layout+-+Final
 */
class MavenRepoJar extends File {
  MavenRepoJar() { exists(MavenRepo mr | mr.getAJarFile() = this) }

  /**
   * Gets the `groupId` of this jar.
   */
  string getGroupId() {
    exists(MavenRepo mr | mr.getAJarFile() = this |
      // Assuming the standard layout, the first part of the directory structure from the Maven
      // repository will be the groupId converted to a path by replacing "." with "/".
      result =
        getParentContainer()
            .getParentContainer()
            .getParentContainer()
            .getAbsolutePath()
            .suffix(mr.getAbsolutePath().length() + 1)
            .replaceAll("/", ".")
    )
  }

  /**
   * DEPRECATED: name changed to `getGroupId` for consistent use of camel-case.
   */
  deprecated string getGroupID() { result = getGroupId() }

  /**
   * Gets the `artifactId` of this jar.
   */
  string getArtifactId() { result = getParentContainer().getParentContainer().getBaseName() }

  /**
   * DEPRECATED: name changed to `getArtifactId` for consistent casing and consistent spelling with Maven.
   */
  deprecated string getArtefactID() { result = getArtifactId() }

  /**
   * Gets the artifact version string of this jar.
   */
  string getVersion() { result = getParentContainer().getBaseName() }

  /**
   * Holds if this jar is an artifact for the given POM or dependency, regardless of which version it is.
   */
  predicate artifactMatches(ProtoPom pom) {
    pom.getGroup().getValue() = getGroupId() and
    pom.getArtifact().getValue() = getArtifactId()
  }

  /**
   * DEPRECATED: name changed to `artifactMatches` for consistent spelling with Maven.
   */
  deprecated predicate artefactMatches(ProtoPom pom) { artifactMatches(pom) }

  /**
   * Holds if this jar is both an artifact for the POM, and has a version string that matches the POM
   * version string. Only soft and hard version matches are supported.
   */
  predicate preciseMatch(ProtoPom pom) {
    artifactMatches(pom) and
    if versionHardMatch(pom)
    then ("[" + getVersion() + "]").matches(pom.getVersionString() + "%")
    else getVersion().matches(pom.getVersionString() + "%")
  }
}
