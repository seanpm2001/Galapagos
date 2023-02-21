// (C) Uri Wilensky. https://github.com/NetLogo/Galapagos

package controllers

import javax.inject.Inject

import play.api.{ Configuration, Environment }
import play.api.mvc.{ AbstractController, Action, AnyContent, ControllerComponents, Request }

import play.twirl.api.Html

class NetTango @Inject() (
  components: ControllerComponents
, configuration: Configuration
, environ: Environment
) extends AbstractController(components) with ResourceSender {

  implicit val environment = environ
  implicit val mode        = environment.mode

  def builder(themed: Boolean, standalone: Boolean): Action[AnyContent] = Action {
    implicit request =>
      Ok(views.html.netTangoBuilder(themed, standalone, if (standalone) InlineTagBuilder else OutsourceTagBuilder))
  }

  def iframeTest: Action[AnyContent] = Action {
    implicit request =>
      Ok(views.html.netTangoIframeTest())
  }

  def library: Action[AnyContent] = Action {
    implicit request =>
      Ok(views.html.mainTheme(views.html.netTangoLibrary(OutsourceTagBuilder)(request, environment), "NetTango Library", None, Html(""), Html(""), "../"))
  }

}
